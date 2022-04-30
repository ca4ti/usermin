#!/usr/local/bin/perl
# Build an RPM package of Usermin

if (-d "$ENV{'HOME'}/redhat") {
	$base_dir = "$ENV{'HOME'}/redhat";
	}
elsif (-d "$ENV{'HOME'}/rpmbuild") {
	$base_dir = "$ENV{'HOME'}/rpmbuild";
	}
else {
	$base_dir = "/usr/src/redhat";
	}
$spec_dir = "$base_dir/SPECS";
$source_dir = "$base_dir/SOURCES";
$rpms_dir = "$base_dir/RPMS/noarch";
$srpms_dir = "$base_dir/SRPMS";

if ($ARGV[0] eq "--nosign" || $ARGV[0] eq "-nosign") {
	$nosign = 1;
	shift(@ARGV);
	}
if ($ARGV[0] eq "--webmail" || $ARGV[0] eq "-webmail") {
	$webmail = 1;
	shift(@ARGV);
	}
$ver = $ARGV[0] || die "usage: makerpm.pl [--webmail] <version> [release]";
$rel = $ARGV[1] || "1";

$oscheck = <<EOF;
if (-r "/etc/.issue") {
	\$etc_issue = `cat /etc/.issue`;
	}
elsif (-r "/etc/issue") {
	\$etc_issue = `cat /etc/issue`;
	}
if (-r "/etc/os-release") {
	\$os_release = `cat /etc/os-release`;
	}
\$uname = `uname -a`;
EOF
open(OS, "os_list.txt");
while(<OS>) {
	chop;
	if (/^([^\t]+)\t+([^\t]+)\t+([^\t]+)\t+([^\t]+)\t*(.*)$/ && $5) {
		$if = $count++ == 0 ? "if" : "elsif";
		$oscheck .= "$if ($5) {\n".
			    "	print \"oscheck='$1'\\n\";\n".
			    "	}\n";
		}
	}
close(OS);
$oscheck =~ s/\\/\\\\/g;
$oscheck =~ s/`/\\`/g;
$oscheck =~ s/\$/\\\$/g;

open(TEMP, "maketemp.pl");
while(<TEMP>) {
	$maketemp .= $_;
	}
close(TEMP);
$maketemp =~ s/\\/\\\\/g;
$maketemp =~ s/`/\\`/g;
$maketemp =~ s/\$/\\\$/g;

$pkgname = $webmail ? "usermin-webmail" : "usermin";
system("cp tarballs/$pkgname-$ver.tar.gz $source_dir") &&
	die "Source file tarballs/$pkgname-$ver.tar.gz not found!";
open(SPEC, ">$spec_dir/$pkgname-$ver.spec");
print SPEC <<EOF;
%global __perl_provides %{nil}

#%define BuildRoot /tmp/%{name}-%{version}
%define __spec_install_post %{nil}

Summary: A web-based user account administration interface
Name: $pkgname
Version: $ver
Release: $rel
Provides: %{name}-%{version}
PreReq: /bin/sh /usr/bin/perl /bin/rm
Requires: /bin/sh /usr/bin/perl /bin/rm
License: Freeware
Group: System/Tools
Source: http://www.webmin.com/download/%{name}-%{version}.tar.gz
Vendor: Jamie Cameron
BuildRoot: /tmp/%{name}-%{version}
BuildArchitectures: noarch
AutoReq: 0
%description
A web-based user account administration interface for Unix systems.

After installation, enter the URL http://localhost:20000/ into your
browser and login as any user on your system.

%prep
%setup -q

%build
(find . -name '*.cgi' ; find . -name '*.pl') | perl perlpath.pl /usr/bin/perl -
rm -f mount/freebsd-mounts-*
rm -f mount/openbsd-mounts-*
chmod -R og-w .

%install
mkdir -p %{buildroot}/usr/libexec/usermin
mkdir -p %{buildroot}/etc/pam.d
cp usermin-pam %{buildroot}/etc/pam.d/usermin
cp -rp * %{buildroot}/usr/libexec/usermin
rm %{buildroot}/usr/libexec/usermin/blue-theme
cp -rp %{buildroot}/usr/libexec/usermin/gray-theme %{buildroot}/usr/libexec/usermin/blue-theme
echo rpm >%{buildroot}/usr/libexec/usermin/install-type
echo $pkgname >%{buildroot}/usr/libexec/usermin/rpm-name

%clean
#%{rmDESTDIR}
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files
%defattr(-,root,root)
/usr/libexec/usermin
%config /etc/pam.d/usermin

%pre
perl <<EOD;
$maketemp
EOD
if [ "\$?" != "0" ]; then
	echo "Failed to create or check temp files directory /tmp/.webmin"
	exit 1
fi
perl >/tmp/.webmin/\$\$.check <<EOD;
$oscheck
EOD
. /tmp/.webmin/\$\$.check
rm -f /tmp/.webmin/\$\$.check
if [ ! -r /etc/usermin/config ]; then
	if [ "\$oscheck" = "" ]; then
		echo Unable to identify operating system
		exit 2
	fi
	if [ "\$USERMIN_PORT\" != \"\" ]; then
		port=\$USERMIN_PORT
	else
		port=20000
	fi
	perl -e 'use Socket; socket(FOO, PF_INET, SOCK_STREAM, getprotobyname("tcp")); setsockopt(FOO, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)); bind(FOO, pack_sockaddr_in(\$ARGV[0], INADDR_ANY)) || exit(1); exit(0);' \$port
	if [ "\$?" != "0" ]; then
		echo Port \$port is already in use
		exit 3
	fi
fi
/bin/true

%post
inetd=`grep "^inetd=" /etc/usermin/miniserv.conf 2>/dev/null | sed -e 's/inetd=//g'`
startafter=0
if [ "\$1" != 1 ]; then
	# Upgrading the RPM, so stop the old Usermin properly
	if [ "\$inetd" != "1" ]; then
		kill -0 `cat /var/usermin/miniserv.pid 2>/dev/null` 2>/dev/null
		if [ "\$?" = 0 ]; then
		  startafter=1
		fi
		/etc/usermin/stop >/dev/null 2>&1 </dev/null
	fi
fi
cd /usr/libexec/usermin
config_dir=/etc/usermin
var_dir=/var/usermin
perl=/usr/bin/perl
autoos=3
if [ "\$USERMIN_PORT\" != \"\" ]; then
	port=\$USERMIN_PORT
else
	port=20000
fi
host=`hostname`
ssl=1
atboot=1
makeboot=1
nochown=1
autothird=1
noperlpath=1
nouninstall=1
nostart=1
export config_dir var_dir perl autoos port ssl nochown autothird noperlpath nouninstall nostart allow makeboot
./setup.sh >/tmp/.webmin/usermin-setup.out 2>&1
chmod 600 /tmp/.webmin/usermin-setup.out
rm -f /var/lock/subsys/usermin
if [ "\$inetd" != "1" -a "\$startafter" = "1" ]; then
	/etc/usermin/stop >/dev/null 2>&1 </dev/null
	/etc/usermin/start >/dev/null 2>&1 </dev/null
	if [ "\$?" != "0" ]; then
		echo "warning: Usermin server cannot be restarted. It is advised to restart it manually by\nrunning \\"/etc/usermin/restart-by-force-kill\\" when upgrade process is finished"
	fi
fi
cat >/etc/usermin/uninstall.sh <<EOFF
#!/bin/sh
printf "Are you sure you want to uninstall Usermin? (y/n) : "
read answer
printf "\\n"
if [ "\\\$answer" = "y" ]; then
	echo "Removing Usermin RPM .."
	rpm -e --nodeps usermin
	echo ".. done"
fi
EOFF
chmod +x /etc/usermin/uninstall.sh
port=`grep "^port=" /etc/usermin/miniserv.conf | sed -e 's/port=//g'`
perl -e 'use Net::SSLeay' >/dev/null 2>/dev/null
sslmode=0
if [ "\$?" = "0" ]; then
	grep ssl=1 /etc/usermin/miniserv.conf >/dev/null 2>/dev/null
	if [ "\$?" = "0" ]; then
		sslmode=1
	fi
fi
if [ "\$1" == 1 ]; then
	if [ "\$sslmode" = "1" ]; then
		echo "Usermin install complete. You can now login to https://\$host:\$port/" >>/tmp/.webmin/usermin-setup.out 2>&1
	else
		echo "Usermin install complete. You can now login to http://\$host:\$port/" >>/tmp/.webmin/usermin-setup.out 2>&1
	fi
	echo "as any user on your system." >>/tmp/.webmin/usermin-setup.out 2>&1
fi
/bin/true

%preun
if [ "\$1" = 0 ]; then
	grep root=/usr/libexec/usermin /etc/usermin/miniserv.conf >/dev/null 2>&1
	if [ "\$?" = 0 ]; then
		# RPM is being removed, and no new version of usermin
		# has taken it's place. Stop the server
		/etc/usermin/stop >/dev/null 2>&1 </dev/null
		/etc/usermin/.stop-init --kill >/dev/null 2>&1 </dev/null
	fi
fi
/bin/true

%postun
if [ "\$1" = 0 ]; then
	grep root=/usr/libexec/usermin /etc/usermin/miniserv.conf >/dev/null 2>&1
	if [ "\$?" = 0 ]; then
		# RPM is being removed, and no new version of usermin
		# has taken it's place. Delete the config files
		rm -rf /etc/usermin /var/usermin
	fi
fi
/bin/true

EOF
close(SPEC);

$cmd = -x "/usr/bin/rpmbuild" ? "rpmbuild" : "rpm";
system("$cmd -ba --target=noarch $spec_dir/$pkgname-$ver.spec") && exit;
system("mv $base_dir/RPMS/noarch/$pkgname-$ver-$rel.noarch.rpm rpm/$pkgname-$ver-$rel.noarch.rpm");
print "Moved to rpm/$pkgname-$ver-$rel.noarch.rpm\n";
system("mv $base_dir/SRPMS/$pkgname-$ver-$rel.src.rpm rpm/$pkgname-$ver-$rel.src.rpm");
print "Moved to rpm/$pkgname-$ver-$rel.src.rpm\n";
system("chown jcameron: rpm/$pkgname-$ver-$rel.noarch.rpm rpm/$pkgname-$ver-$rel.src.rpm");
if (!$nosign) {
	system("rpm --resign rpm/$pkgname-$ver-$rel.noarch.rpm rpm/$pkgname-$ver-$rel.src.rpm");
	}

if (-d "/usr/local/webadmin/rpm/yum") {
	# Add to our repository
	system("cp rpm/$pkgname-$ver-$rel.noarch.rpm /usr/local/webadmin/rpm/yum");
	}

