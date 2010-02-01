#!/usr/bin/perl

use LWP 5.64;
use HTTP::Request::Common;
use Net::Ping;

$#ARGV+1 == 2 or die "$0: you must specify IP and hostname";

$timeout = 120; #minimum is 6 seconds
$path_ca = "/home/user/phones/certs";

$Cert_Organization = "Example Organization";
$Cert_OrganizationUnit = "Example Unit";
$Cert_City = "Greve";
$Cert_State = "Denmark";
$Cert_Country = "DK";
$Cert_KeySize = "1";

$Net_ProfileName = "Example profile";
$Net_SSID = "Wireless Phones";
$Net_CallPoweSaveMode = "2";    # 1 - FAST, 2 - CAM
$Net_80211Mode = "5";		# EAP-TLS
$Net_WLANSecurityMode = "7";	# EAP-TLS
$Net_ExportCredentials = "false";
$Net_ExportHidden = "0";
$Net_WLANEAPTLSCertType = "1";	# User generated
$Net_DHCPEnabled = "true";
$Net_AlternateTFTP = "false";


$host="$ARGV[0]";
$hostname="$ARGV[1]";

my $browser = LWP::UserAgent->new;

$browser->credentials(
  "$host:443",
  "Cisco Unified Wireless IP Phone 7925G",
  "admin" => "Cisco"
);


&systemtime;
&systemrestart;

&certauthserver;
&systemrestart;

&certreq;
&certsignrequest;
&certupload;

&configurenetwork;
exit(0);

sub certreq {
  print "User Certificate Installation\n";
  my $url = "https://$host/Forms/CertReq";
  my $response = $browser->request(POST $url,
	Content_Type => 'form-data',
	Content => 
	       [CommonName => "CP-7925G-$hostname",
		Organization => $Cert_Organization,
		OrganizationUnit => $Cert_OrganizationUnit,
		City => $Cert_City,
		State => $Cert_State ,
		Country => $Cert_Country,
		KeySize => $Cert_KeySize,
		CACertFile => ["$path_ca/ca.der"],
		Submit => 'Submit'
	]);  $_ = $response->as_string;
  /Location: .*CertGenCSRStatus/ or die "Invalid User Certificate request";
  sleep 5;
  my $url = "https://$host/Forms/CertGenCSR";
  my $response = $browser->request(GET $url);
  $certificat = $response->as_string;
#  /.*Generating Certificate Signing Request/ or die "Not Generating Certificate Signing Request";
  sleep 5;
}

sub certsignrequest {
  print "User Certificate Installation - Certificate Signing Request\n";
  my $url = "https://$host/CertSignRequest";
  my $response = $browser->request(GET $url);
  $certificat = $response->as_string;
#  print $certificat;
  $/ = "";
  $certificat =~ s/.*(-----BEGIN CERTIFICATE REQUEST-----.*-----END CERTIFICATE REQUEST-----).*/$1/msg or die "Signing Request error: No certificate request found";

  $file = "$path_ca/$hostname";
  $file_csr = "$file.csr";
  $file_pem = "$file.pem";
  $file_der = "$file.der";

  open(FH, "> $file_csr") or die "Can't write to $file_csr: $!";
  print FH $certificat;
  close(FH);
  
  print "Calling openssl to sign certificat request.\n";
  system("openssl x509 -req -in $file_csr -extfile $path_ca/client.cnf -CA $path_ca/ca.pem -CAkey $path_ca/ca.key -CAcreateserial -out $file_pem -days 3000 -extensions xpclient_ext -extfile $path_ca/xpextensions -passin pass:whatever") == 0 or die "openssl failed: $!"; 

  print "Calling openssl to convert signed certificat request for Cisco Phone.\n";
  system("openssl x509 -in $file_pem -inform PEM -out $file_der -outform DER") == 0 or die "openssl failed: $!";

}

sub certauthserver {
  print "Upload CA\n";
  my $url = "https://$host/Forms/CertAuthServer";
  my $response = $browser->request(POST $url,
	Content_Type => 'form-data',
	Content => 
	  [PhoneCertFile => ["$path_ca/ca.der"],
	   Submit        => 'Submit'
	]);
  $_ = $response->as_string;
  /Location: .*StatusMessage\?23,0/ or die "Invalid CA";
  print "CA: ok\n";
}

sub certupload {
  print "User Certificate Installation - Upload Signed Certificate\n";
  my $url = "https://$host/Forms/CertUpload";
  my $response = $browser->request(POST $url,
	Content_Type => 'form-data',
	Content => 
	       [PhoneCertFile => ["$file_der"],
		Submit => 'Import'
	       ]
	);
  $_ = $response->as_string;
  /Location: .*StatusMessage\?19,0/ or die "Invalid signed certificate";
  print "Signed Certificate: ok\n";
}

sub systemtime {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
  $year += 1900;
  my @abbr = qw( January February March April May June July August September October November December);
  my $datetime = sprintf "%s %02d, %04d     %02d:%02d:%02d", $abbr[$mon], $mday, $year, $hour, $min, $sec;

  print "Seting clock: $datetime\n";

  my $url = "https://$host/Forms/SystemTime";
  my $response = $browser->request(POST $url,
	[LocalDateAndTime => "$datetime",
	 Submit           => 'Set Phone to Local Date & Time'
	]);
  $_ = $response->as_string;
  /Location: .*SystemTime/ or die "Invalid date or clock";
  print "Clock: ok\n";
}

sub systemrestart {
  print "Starting restart\n";
  my $url = "https://$host/Forms/SystemRestart";
  my $response = $browser->request(POST $url, [Submit => 'Restart']);
  $_ = $response->as_string;
  /Location: .*StatusMessage\?22,0/ or die "Could not restart";
  print "Restarting and waiting for $timeout seconds\n";
  sleep 5;

  $p=Net::Ping->new();

  if ( $p->ping($host,$timeout-5) ) {
    print "$host is alive.\n"; 
  } else {
    print "$host is NOT alive after $timeout seconds.\n";
    exit 1;
  }

  $p->close();
}

sub configurenetwork {
  print "Configure Network\n";

  # I don't know why ... but we need to make this request
  my $url = "https://$host/NetworkProfile?1";
  my $response = $browser->request(GET $url);
  $_ = $response->as_string;

  my $url = "https://$host/Forms/NetworkProfile?1";
  my $response = $browser->request(POST $url, Content =>
"ProfileName=$Net_ProfileName&SSID=$Net_SSID&CallPoweSaveMode=$Net_CallPoweSaveMode&80211Mode=$Net_80211Mode&WLANSecurityMode=$Net_WLANSecurityMode&ExportCredentials=$Net_ExportCredentials&ExportHidden=$Net_ExportHidden&WLANEAPTLSCertType=$Net_WLANEAPTLSCertType&DHCPEnabled=$Net_DHCPEnabled&AlternateTFTP=$Net_AlternateTFTP&Submit=Save"
    );
  $_ = $response->as_string;
  /Location: .*NetworkProfile\?1/ or die "Network not configured";
}

