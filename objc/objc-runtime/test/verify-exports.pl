#!/usr/bin/perl

# verify-exports.pl
# Check exports in a library vs. declarations in header files.
# usage: verify-exports.pl /path/to/dylib /glob/path/to/headers decl-prefix [-arch <arch>] [/path/to/project~dst]
# example: verify-exports.pl /usr/lib/libobjc.A.dylib '/usr/{local/,}include/objc/*' OBJC_EXPORT -arch x86_64 /tmp/objc-test.roots/objc-test~dst

# requirements:
# - every export must have an @interface or specially-marked declaration
# - every @interface or specially-marked declaration must have an availability macro
# - no C++ exports allowed

use strict;
use File::Basename;
use File::Glob ':glob';

my $bad = 0;

$0 = basename($0, ".pl");
my $usage = "/path/to/dylib /glob/path/to/headers decl-prefix [-arch <arch>] [-sdk sdkname] [/path/to/project~dst]";

my $lib_arg = shift || die "$usage";
die "$usage" unless ($lib_arg =~ /^\//);
my $headers_arg = shift || die "$usage";
my $export_arg = shift || die "$usage";

my $arch = "x86_64";
if ($ARGV[0] eq "-arch") {
    shift;
    $arch = shift || die "$0: -arch requires an architecture";
}
my $sdk = "system";
if ($ARGV[0] eq "-sdk") {
    shift;
    $sdk = shift || die "$0: -sdk requires an SDK name";
}

my $root = shift || "";


# Collect symbols from dylib.
my $lib_path = "$root$lib_arg";
die "$0: file not found: $lib_path\n" unless -e $lib_path;

my %symbols;
my @symbollines = `nm -arch $arch '$lib_path'`;
die "$0: nm failed: (arch $arch) $lib_path\n" if ($?);
for my $line (@symbollines) {
    chomp $line;
    (my $type, my $name) = ($line =~ /^[[:xdigit:]]*\s+(.) (.*)$/);
    if ($type =~ /^[A-TV-Z]$/) {
        $symbols{$name} = 1;
    } else {
        # undefined (U) or non-external - ignore
    }
}

# Complain about C++ exports
for my $symbol (keys %symbols) {
    if ($symbol =~ /^__Z/) {
        print "BAD: C++ export '$symbol'\n"; $bad++;
    }
}


# Translate arch to unifdef(1) parameters: archnames, __LP64__, __OBJC2__
my @archnames = ("x86_64", "i386", "arm", "armv6", "armv7");
my %archOBJC1   = (i386 => 1);
my %archLP64    = (x86_64 => 1);
my @archparams;

my $OBJC1 = ($archOBJC1{$arch} && $sdk !~ /^iphonesimulator/);

if ($OBJC1) { 
    push @archparams, "-U__OBJC2__"; 
} else { 
    push @archparams, "-D__OBJC2__=1"; 
}

if ($archLP64{$arch}) { push @archparams, "-D__LP64__=1"; } 
else { push @archparams, "-U__LP64__"; }

for my $archname (@archnames) {
    if ($archname eq $arch) {
        push @archparams, "-D__${archname}__=1";
        push @archparams, "-D__$archname=1";
    } else {
        push @archparams, "-U__${archname}__";
        push @archparams, "-U__$archname";
    }
}

# TargetConditionals.h
# fixme iphone and simulator
push @archparams, "-DTARGET_OS_WIN32=0";
push @archparams, "-DTARGET_OS_EMBEDDED=0";
push @archparams, "-DTARGET_OS_IPHONE=0";
push @archparams, "-DTARGET_OS_MAC=1";

# Gather declarations from header files
# A C declaration starts with $export_arg and ends with ';'
# A class declaration is @interface plus the line before it.
my $unifdef_cmd = "/usr/bin/unifdef " . join(" ", @archparams);
my @cdecls;
my @classdecls;
for my $header_path(bsd_glob("$root$headers_arg",GLOB_BRACE)) {
    my $header;
    # feed through unifdef(1) first to strip decls from other archs
    # fixme strip other SDKs as well
    open($header, "$unifdef_cmd < '$header_path' |");
    my $header_contents = join("", <$header>);

    # C decls
    push @cdecls, ($header_contents =~ /^\s*$export_arg\s+([^;]*)/msg);

    # ObjC classes, but not categories.
    # fixme ivars
    push @classdecls, ($header_contents =~ /^([^\n]*\n\s*\@interface\s+[^(\n]+\n)/mg);
}

# Find name and availability of C declarations
my %declarations;
for my $cdecl (@cdecls) {
    $cdecl =~ s/\n/ /mg;  # strip newlines

    # Pull availability macro off the end:
    # __OSX_AVAILABLE_*(*)
    # AVAILABLE_MAC_OS_X_VERSION_*
    # OBJC2_UNAVAILABLE
    # OBJC_HASH_AVAILABILITY
    # OBJC_MAP_AVAILABILITY
    # UNAVAILABLE_ATTRIBUTE
    # (DEPRECATED_ATTRIBUTE is not good enough. Be specific.)
    my $avail = undef;
    my $cdecl2;
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(__OSX_AVAILABLE_\w+\([a-zA-Z0-9_, ]+\))\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(AVAILABLE_MAC_OS_X_VERSION_\w+)\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(OBJC2_UNAVAILABLE)\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(OBJC_GC_UNAVAILABLE)\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(OBJC_ARC_UNAVAILABLE)\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(OBJC_HASH_AVAILABILITY)\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(OBJC_MAP_AVAILABILITY)\s*$/) if (!defined $avail);
    ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(UNAVAILABLE_ATTRIBUTE)\s*$/) if (!defined $avail);
    # ($cdecl2, $avail) = ($cdecl =~ /^(.*)\s+(DEPRECATED_\w+)\s*$/) if (!defined $avail);
    $cdecl2 = $cdecl if (!defined $cdecl2);

    # Extract declaration name (assumes availability macro is already gone):
    # `(*xxx)` (function pointer)
    # `xxx(`   (function)
    # `xxx`$` or `xxx[nnn]$` (variable or array variable)
    my $name = undef;
    ($name) = ($cdecl2 =~ /^[^(]*\(\s*\*\s*(\w+)\s*\)/) if (!defined $name);
    ($name) = ($cdecl2 =~ /(\w+)\s*\(/) if (!defined $name);
    ($name) = ($cdecl2 =~ /(\w+)\s*(?:\[\d*\]\s*)*$/) if (!defined $name);

    if (!defined $name) {
        print "BAD: unintellible declaration:\n    $cdecl\n"; $bad++;
    } elsif (!defined $avail) {
        print "BAD: no availability on declaration of '$name':\n    $cdecl\n"; $bad++;
    }

    if ($avail eq "UNAVAILABLE_ATTRIBUTE")
    {
        $declarations{$name} = "unavailable";
    } elsif ($avail eq "OBJC2_UNAVAILABLE"  &&  ! $OBJC1) {
        # fixme OBJC2_UNAVAILABLE may or may not have an exported symbol
        # $declarations{$name} = "unavailable";
    } else {
        $declarations{"_$name"} = "available";
    }
}

# Find name and availability of Objective-C classes
for my $classdecl (@classdecls) {
    $classdecl =~ s/\n/ /mg;  # strip newlines

    # Pull availability macro off the front:
    # __OSX_AVAILABLE_*(*)
    # AVAILABLE_MAC_OS_X_VERSION_*
    # OBJC2_UNAVAILABLE
    # OBJC_HASH_AVAILABILITY
    # OBJC_MAP_AVAILABILITY
    # UNAVAILABLE_ATTRIBUTE
    # (DEPRECATED_ATTRIBUTE is not good enough. Be specific.)
    my $avail = undef;
    my $classdecl2;
    ($avail, $classdecl2) = ($classdecl =~ /^\s*(__OSX_AVAILABLE_\w+\([a-zA-Z0-9_, ]+\))\s*(.*)$/) if (!defined $avail);
    ($avail, $classdecl2) = ($classdecl =~ /^\s*(AVAILABLE_MAC_OS_X_VERSION_\w+)\s*(.*)$/) if (!defined $avail);
    ($avail, $classdecl2) = ($classdecl =~ /^\s*(OBJC2_UNAVAILABLE)\s*(.*)$/) if (!defined $avail);
    ($avail, $classdecl2) = ($classdecl =~ /^\s*(OBJC_HASH_AVAILABILITY)\s*(.*)$/) if (!defined $avail);
    ($avail, $classdecl2) = ($classdecl =~ /^\s*(OBJC_MAP_AVAILABILITY)\s*(.*)$/) if (!defined $avail);
    ($avail, $classdecl2) = ($classdecl =~ /^\s*(UNAVAILABLE_ATTRIBUTE)\s*(.*)$/) if (!defined $avail);
    # ($avail, $classdecl2) = ($classdecl =~ /^\s*(DEPRECATED_\w+)\s*(.*)$/) if (!defined $avail);
    $classdecl2 = $classdecl if (!defined $classdecl2);

    # Extract class name.
    my $name = undef;
    ($name) = ($classdecl2 =~ /\@interface\s+(\w+)/);

    if (!defined $name) {
        print "BAD: unintellible declaration:\n    $classdecl\n"; $bad++;
    } elsif (!defined $avail) {
        print "BAD: no availability on declaration of '$name':\n    $classdecl\n"; $bad++;
    }

    my $availability;
    if ($avail eq "UNAVAILABLE_ATTRIBUTE") {
	$availability = "unavailable";
    } elsif ($avail eq "OBJC2_UNAVAILABLE"  &&  ! $OBJC1) {
        # fixme OBJC2_UNAVAILABLE may or may not have an exported symbol
        # $declarations{$name} = "unavailable";
	$availability = undef;
    } else {
	$availability = "available";
    }

    if (! $OBJC1) {
        $declarations{"_OBJC_CLASS_\$_$name"} = $availability;
        $declarations{"_OBJC_METACLASS_\$_$name"} = $availability;
        # fixme ivars
        $declarations{"_OBJC_IVAR_\$_$name.isa"} = $availability if ($name eq "Object");
    } else {
        $declarations{".objc_class_name_$name"} = $availability;
    }
}

# All exported symbols must have an export declaration
my @missing_symbols;
for my $name (keys %symbols) {
    my $avail = $declarations{$name};
    if ($avail eq "unavailable"  ||  !defined $avail) {
        push @missing_symbols, $name;
    }
}
for my $symbol (sort @missing_symbols) {
    print "BAD: symbol $symbol has no export declaration\n"; $bad++;
}


# All export declarations must have an exported symbol
my @missing_decls;
for my $name (keys %declarations) {
    my $avail = $declarations{$name};
    my $hasSymbol = exists $symbols{$name};
    if ($avail ne "unavailable"  &&  !$hasSymbol) {
        push @missing_decls, $name;
    }
}
for my $decl (sort @missing_decls) {
    print "BAD: declaration $decl has no exported symbol\n"; $bad++;
}

print "OK: verify-exports\n" unless $bad;
exit ($bad ? 1 : 0);
