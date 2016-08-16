#!/usr/bin/perl

# test.pl
# Run unit tests.

use strict;
use File::Basename;

chdir dirname $0;
chomp (my $DIR = `pwd`);

my $TESTLIBNAME = "libobjc.A.dylib";
my $TESTLIBPATH = "/usr/lib/$TESTLIBNAME";

my $BUILDDIR = "/tmp/test-$TESTLIBNAME-build";

# xterm colors
my $red = "\e[41;37m";
my $yellow = "\e[43;30m";
my $nocolor = "\e[0m";

# clean, help
if (scalar(@ARGV) == 1) {
    my $arg = $ARGV[0];
    if ($arg eq "clean") {
        my $cmd = "rm -rf $BUILDDIR *~";
        print "$cmd\n";
        `$cmd`;
        exit 0;
    }
    elsif ($arg eq "-h" || $arg eq "-H" || $arg eq "-help" || $arg eq "help") {
        print(<<END);
usage: $0 [options] [testname ...]
       $0 clean
       $0 help

testname:
    `testname` runs a specific test. If no testnames are given, runs all tests.

options:
    ARCH=<arch>
    OS=<sdk name>[sdk version][-<deployment target>[-<run target>]]
    ROOT=/path/to/project.roots/

    CC=<compiler name>

    LANGUAGE=c,c++,objective-c,objective-c++,swift
    MEM=mrc,arc,gc
    STDLIB=libc++,libstdc++
    GUARDMALLOC=0|1|before|after

    BUILD=0|1
    RUN=0|1
    VERBOSE=0|1|2

examples:

    test installed library, x86_64, no gc
    $0

    test buildit-built root, i386 and x86_64, MRC and ARC and GC, clang compiler
    $0 ARCH=i386,x86_64 ROOT=/tmp/libclosure.roots MEM=mrc,arc,gc CC=clang

    test buildit-built root with iOS simulator, deploy to iOS 7, run on iOS 8
    $0 ARCH=i386 ROOT=/tmp/libclosure.roots OS=iphonesimulator-7.0-8.0

    test buildit-built root on attached iOS device
    $0 ARCH=armv7 ROOT=/tmp/libclosure.roots OS=iphoneos
END
        exit 0;
    }
}

#########################################################################
## Tests

my %ALL_TESTS;

#########################################################################
## Variables for use in complex build and run rules

# variable         # example value

# things you can multiplex on the command line
# ARCH=i386,x86_64,armv6,armv7
# OS=macosx,iphoneos,iphonesimulator (plus sdk/deployment/run versions)
# LANGUAGE=c,c++,objective-c,objective-c++,swift
# CC=clang,gcc-4.2,llvm-gcc-4.2
# MEM=mrc,arc,gc
# STDLIB=libc++,libstdc++
# GUARDMALLOC=0,1,before,after

# things you can set once on the command line
# ROOT=/path/to/project.roots
# BUILD=0|1
# RUN=0|1
# VERBOSE=0|1|2



my $BUILD;
my $RUN;
my $VERBOSE;

my $crashcatch = <<'END';
// interpose-able code to catch crashes, print, and exit cleanly
#include <signal.h>
#include <string.h>
#include <unistd.h>

// from dyld-interposing.h
#define DYLD_INTERPOSE(_replacement,_replacee) __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

static void catchcrash(int sig) 
{
    const char *msg;
    switch (sig) {
    case SIGILL:  msg = "CRASHED: SIGILL\\n";  break;
    case SIGBUS:  msg = "CRASHED: SIGBUS\\n";  break;
    case SIGSYS:  msg = "CRASHED: SIGSYS\\n";  break;
    case SIGSEGV: msg = "CRASHED: SIGSEGV\\n"; break;
    case SIGTRAP: msg = "CRASHED: SIGTRAP\\n"; break;
    case SIGABRT: msg = "CRASHED: SIGABRT\\n"; break;
    default: msg = "SIG\?\?\?\?\\n"; break;
    }
    write(STDERR_FILENO, msg, strlen(msg));
    _exit(0);
}

static void setupcrash(void) __attribute__((constructor));
static void setupcrash(void) 
{
    signal(SIGILL, &catchcrash);
    signal(SIGBUS, &catchcrash);
    signal(SIGSYS, &catchcrash);
    signal(SIGSEGV, &catchcrash);
    signal(SIGTRAP, &catchcrash);
    signal(SIGABRT, &catchcrash);
}


static int hacked = 0;
ssize_t hacked_write(int fildes, const void *buf, size_t nbyte)
{
    if (!hacked) {
        setupcrash();
        hacked = 1;
    }
    return write(fildes, buf, nbyte);
}

DYLD_INTERPOSE(hacked_write, write);

END


#########################################################################
## Harness


# map language to buildable extensions for that language
my %extensions_for_language = (
    "c"     => ["c"],     
    "objective-c" => ["c", "m"], 
    "c++" => ["c", "cc", "cp", "cpp", "cxx", "c++"], 
    "objective-c++" => ["c", "m", "cc", "cp", "cpp", "cxx", "c++", "mm"], 
    "swift" => ["swift"], 

    "any" => ["c", "m", "cc", "cp", "cpp", "cxx", "c++", "mm", "swift"], 
    );

# map extension to languages
my %languages_for_extension = (
    "c" => ["c", "objective-c", "c++", "objective-c++"], 
    "m" => ["objective-c", "objective-c++"], 
    "mm" => ["objective-c++"], 
    "cc" => ["c++", "objective-c++"], 
    "cp" => ["c++", "objective-c++"], 
    "cpp" => ["c++", "objective-c++"], 
    "cxx" => ["c++", "objective-c++"], 
    "c++" => ["c++", "objective-c++"], 
    "swift" => ["swift"], 
    );

# Run some newline-separated commands like `make` would, stopping if any fail
# run("cmd1 \n cmd2 \n cmd3")
sub make {
    my $output = "";
    my @cmds = split("\n", $_[0]);
    die if scalar(@cmds) == 0;
    $? = 0;
    foreach my $cmd (@cmds) {
        chomp $cmd;
        next if $cmd =~ /^\s*$/;
        $cmd .= " 2>&1";
        print "$cmd\n" if $VERBOSE;
        $output .= `$cmd`;
        last if $?;
    }
    print "$output\n" if $VERBOSE;
    return $output;
}

sub chdir_verbose {
    my $dir = shift;
    print "cd $dir\n" if $VERBOSE;
    chdir $dir || die;
}


# Return test names from the command line.
# Returns all tests if no tests were named.
sub gettests {
    my @tests;

    foreach my $arg (@ARGV) {
        push @tests, $arg  if ($arg !~ /=/  &&  $arg !~ /^-/);
    }

    opendir(my $dir, $DIR) || die;
    while (my $file = readdir($dir)) {
        my ($name, $ext) = ($file =~ /^([^.]+)\.([^.]+)$/);
        next if ! $languages_for_extension{$ext};

        open(my $in, "< $file") || die "$file";
        my $contents = join "", <$in>;
        if (defined $ALL_TESTS{$name}) {
            print "${yellow}SKIP: multiple tests named '$name'; skipping file '$file'.${nocolor}\n";
        } else {
            $ALL_TESTS{$name} = $ext  if ($contents =~ m#^[/*\s]*TEST_#m);
        }
        close($in);
    }
    closedir($dir);

    if (scalar(@tests) == 0) {
        @tests = keys %ALL_TESTS;
    }

    @tests = sort @tests;

    return @tests;
}


# Turn a C compiler name into a C++ compiler name.
sub cplusplus {
    my ($c) = @_;
    if ($c =~ /cc/) {
        $c =~ s/cc/\+\+/;
        return $c;
    }
    return $c . "++";                         # e.g. clang => clang++
}

# Turn a C compiler name into a Swift compiler name
sub swift {
    my ($c) = @_;
    $c =~ s#[^/]*$#swift#;
    return $c;
}

# Returns an array of all sdks from `xcodebuild -showsdks`
my @sdks_memo;
sub getsdks {
    if (!@sdks_memo) {
        @sdks_memo = (`xcodebuild -showsdks` =~ /-sdk (.+)$/mg);
    }
    return @sdks_memo;
}

my %sdk_path_memo = {};
sub getsdkpath {
    my ($sdk) = @_;
    if (!defined $sdk_path_memo{$sdk}) {
        ($sdk_path_memo{$sdk}) = (`xcodebuild -version -sdk '$sdk' Path` =~ /^\s*(.+?)\s*$/);
    }
    return $sdk_path_memo{$sdk};
}

# Extract a version number from a string.
# Ignore trailing "internal".
sub versionsuffix {
    my ($str) = @_;
    my ($vers) = ($str =~ /([0-9]+\.[0-9]+)(?:\.?internal)?$/);
    return $vers;
}
sub majorversionsuffix {
    my ($str) = @_;
    my ($vers) = ($str =~ /([0-9]+)\.[0-9]+(?:\.?internal)?$/);
    return $vers;
}
sub minorversionsuffix {
    my ($str) = @_;
    my ($vers) = ($str =~ /[0-9]+\.([0-9]+)(?:\.?internal)?$/);
    return $vers;
}

# Compares two SDK names and returns the newer one.
# Assumes the two SDKs are the same OS.
sub newersdk {
    my ($lhs, $rhs) = @_;

    # Major version wins.
    my $lhsMajor = majorversionsuffix($lhs);
    my $rhsMajor = majorversionsuffix($rhs);
    if ($lhsMajor > $rhsMajor) { return $lhs; }
    if ($lhsMajor < $rhsMajor) { return $rhs; }

    # Minor version wins.
    my $lhsMinor = minorversionsuffix($lhs);
    my $rhsMinor = minorversionsuffix($rhs);
    if ($lhsMinor > $rhsMinor) { return $lhs; }
    if ($lhsMinor < $rhsMinor) { return $rhs; }

    # Lexically-last wins (i.e. internal is better than not internal)
    if ($lhs gt $rhs) { return $lhs; }
    return $rhs;
}

# Returns whether the given sdk supports -lauto
sub supportslibauto {
    my ($sdk) = @_;
    return 1 if $sdk =~ /^macosx/;
    return 0;
}

# print text with a colored prefix on each line
sub colorprint {
    my $color = shift;
    while (my @lines = split("\n", shift)) {
        for my $line (@lines) {
            chomp $line;
            print "$color $nocolor$line\n";
        }
    }
}

sub rewind {
    seek($_[0], 0, 0);
}

# parse name=value,value pairs
sub readconditions {
    my ($conditionstring) = @_;

    my %results;
    my @conditions = ($conditionstring =~ /\w+=(?:[^\s,]+,?)+/g);
    for my $condition (@conditions) {
        my ($name, $values) = ($condition =~ /(\w+)=(.+)/);
        $results{$name} = [split ',', $values];
    }

    return %results;
}

sub check_output {
    my %C = %{shift()};
    my $name = shift;
    my @output = @_;

    my %T = %{$C{"TEST_$name"}};

    # Quietly strip MallocScribble before saving the "original" output 
    # because it is distracting.
    filter_malloc(\@output);

    my @original_output = @output;

    # Run result-checking passes, reducing @output each time
    my $xit = 1;
    my $bad = "";
    my $warn = "";
    my $runerror = $T{TEST_RUN_OUTPUT};
    filter_hax(\@output);
    filter_verbose(\@output);
    filter_simulator(\@output);
    $warn = filter_warn(\@output);
    $bad |= filter_guardmalloc(\@output) if ($C{GUARDMALLOC});
    $bad |= filter_valgrind(\@output) if ($C{VALGRIND});
    $bad = filter_expected(\@output, \%C, $name) if ($bad eq "");
    $bad = filter_bad(\@output)  if ($bad eq "");

    # OK line should be the only one left
    $bad = "(output not 'OK: $name')" if ($bad eq ""  &&  (scalar(@output) != 1  ||  $output[0] !~ /^OK: $name/));
    
    if ($bad ne "") {
        print "${red}FAIL: /// test '$name' \\\\\\$nocolor\n";
        colorprint($red, @original_output);
        print "${red}FAIL: \\\\\\ test '$name' ///$nocolor\n";
        print "${red}FAIL: $name: $bad$nocolor\n";
        $xit = 0;
    } 
    elsif ($warn ne "") {
        print "${yellow}PASS: /// test '$name' \\\\\\$nocolor\n";
        colorprint($yellow, @original_output);
        print "${yellow}PASS: \\\\\\ test '$name' ///$nocolor\n";
        print "PASS: $name (with warnings)\n";
    }
    else {
        print "PASS: $name\n";
    }
    return $xit;
}

sub filter_expected
{
    my $outputref = shift;
    my %C = %{shift()};
    my $name = shift;

    my %T = %{$C{"TEST_$name"}};
    my $runerror = $T{TEST_RUN_OUTPUT}  ||  return "";

    my $bad = "";

    my $output = join("\n", @$outputref) . "\n";
    if ($output !~ /$runerror/) {
	$bad = "(run output does not match TEST_RUN_OUTPUT)";
	@$outputref = ("FAIL: $name");
    } else {
	@$outputref = ("OK: $name");  # pacify later filter
    }

    return $bad;
}

sub filter_bad
{
    my $outputref = shift;
    my $bad = "";

    my @new_output;
    for my $line (@$outputref) {
	if ($line =~ /^BAD: (.*)/) {
	    $bad = "(failed)";
	} else {
	    push @new_output, $line;
	}
    }

    @$outputref = @new_output;
    return $bad;
}

sub filter_warn
{
    my $outputref = shift;
    my $warn = "";

    my @new_output;
    for my $line (@$outputref) {
	if ($line !~ /^WARN: (.*)/) {
	    push @new_output, $line;
        } else {
	    $warn = "(warned)";
	}
    }

    @$outputref = @new_output;
    return $warn;
}

sub filter_verbose
{
    my $outputref = shift;

    my @new_output;
    for my $line (@$outputref) {
	if ($line !~ /^VERBOSE: (.*)/) {
	    push @new_output, $line;
	}
    }

    @$outputref = @new_output;
}

sub filter_simulator
{
    my $outputref = shift;

    my @new_output;
    for my $line (@$outputref) {
	if ($line !~ /No simulator devices appear to be running/) {
	    push @new_output, $line;
	}
    }

    @$outputref = @new_output;
}

sub filter_simulator
{
    my $outputref = shift;

    my @new_output;
    for my $line (@$outputref) {
	if ($line !~ /No simulator devices appear to be running/) {
	    push @new_output, $line;
	}
    }

    @$outputref = @new_output;
}

sub filter_hax
{
    my $outputref = shift;

    my @new_output;
    for my $line (@$outputref) {
	if ($line !~ /Class OS_tcp_/) {
	    push @new_output, $line;
	}
    }

    @$outputref = @new_output;
}

sub filter_valgrind
{
    my $outputref = shift;
    my $errors = 0;
    my $leaks = 0;

    my @new_output;
    for my $line (@$outputref) {
	if ($line =~ /^Approx: do_origins_Dirty\([RW]\): missed \d bytes$/) {
	    # --track-origins warning (harmless)
	    next;
	}
	if ($line =~ /^UNKNOWN __disable_threadsignal is unsupported. This warning will not be repeated.$/) {
	    # signals unsupported (harmless)
	    next;
	}
	if ($line =~ /^UNKNOWN __pthread_sigmask is unsupported. This warning will not be repeated.$/) {
	    # signals unsupported (harmless)
	    next;
	}
	if ($line !~ /^^\.*==\d+==/) {
	    # not valgrind output
	    push @new_output, $line;
	    next;
	}

	my ($errcount) = ($line =~ /==\d+== ERROR SUMMARY: (\d+) errors/);
	if (defined $errcount  &&  $errcount > 0) {
	    $errors = 1;
	}

	(my $leakcount) = ($line =~ /==\d+==\s+(?:definitely|possibly) lost:\s+([0-9,]+)/);
	if (defined $leakcount  &&  $leakcount > 0) {
	    $leaks = 1;
	}
    }

    @$outputref = @new_output;

    my $bad = "";
    $bad .= "(valgrind errors)" if ($errors);
    $bad .= "(valgrind leaks)" if ($leaks);
    return $bad;
}



sub filter_malloc
{
    my $outputref = shift;
    my $errors = 0;

    my @new_output;
    my $count = 0;
    for my $line (@$outputref) {
        # Ignore MallocScribble prologue.
        # Ignore MallocStackLogging prologue.
        if ($line =~ /malloc: enabling scribbling to detect mods to free/  ||  
            $line =~ /Deleted objects will be dirtied by the collector/  ||
            $line =~ /malloc: stack logs being written into/  ||  
            $line =~ /malloc: stack logs deleted from/  ||  
            $line =~ /malloc: process \d+ no longer exists/  ||  
            $line =~ /malloc: recording malloc and VM allocation stacks/)
        {
            next;
	}

        # not malloc output
        push @new_output, $line;

    }

    @$outputref = @new_output;
}

sub filter_guardmalloc
{
    my $outputref = shift;
    my $errors = 0;

    my @new_output;
    my $count = 0;
    for my $line (@$outputref) {
	if ($line !~ /^GuardMalloc\[[^\]]+\]: /) {
	    # not guardmalloc output
	    push @new_output, $line;
	    next;
	}

        # Ignore 4 lines of guardmalloc prologue.
        # Anything further is a guardmalloc error.
        if (++$count > 4) {
            $errors = 1;
        }
    }

    @$outputref = @new_output;

    my $bad = "";
    $bad .= "(guardmalloc errors)" if ($errors);
    return $bad;
}

# TEST_SOMETHING
# text
# text
# END
sub extract_multiline {
    my ($flag, $contents, $name) = @_;
    if ($contents =~ /$flag\n/) {
        my ($output) = ($contents =~ /$flag\n(.*?\n)END[ *\/]*\n/s);
        die "$name used $flag without END\n"  if !defined($output);
        return $output;
    }
    return undef;
}


# TEST_SOMETHING
# text
# OR
# text
# END
sub extract_multiple_multiline {
    my ($flag, $contents, $name) = @_;
    if ($contents =~ /$flag\n/) {
        my ($output) = ($contents =~ /$flag\n(.*?\n)END[ *\/]*\n/s);
        die "$name used $flag without END\n"  if !defined($output);

        $output =~ s/\nOR\n/\n|/sg;
        $output = "^(" . $output . ")\$";
        return $output;
    }
    return undef;
}


sub gather_simple {
    my $CREF = shift;
    my %C = %{$CREF};
    my $name = shift;
    chdir_verbose $DIR;

    my $ext = $ALL_TESTS{$name};
    my $file = "$name.$ext";
    return 0 if !$file;

    # search file for 'TEST_CONFIG' or '#include "test.h"'
    # also collect other values:
    # TEST_DISABLED disable test with an optional message
    # TEST_CRASHES test is expected to crash
    # TEST_CONFIG test conditions
    # TEST_ENV environment prefix
    # TEST_CFLAGS compile flags
    # TEST_BUILD build instructions
    # TEST_BUILD_OUTPUT expected build stdout/stderr
    # TEST_RUN_OUTPUT expected run stdout/stderr
    open(my $in, "< $file") || die;
    my $contents = join "", <$in>;
    
    my $test_h = ($contents =~ /^\s*#\s*(include|import)\s*"test\.h"/m);
    my ($disabled) = ($contents =~ /\b(TEST_DISABLED\b.*)$/m);
    my $crashes = ($contents =~ /\bTEST_CRASHES\b/m);
    my ($conditionstring) = ($contents =~ /\bTEST_CONFIG\b(.*)$/m);
    my ($envstring) = ($contents =~ /\bTEST_ENV\b(.*)$/m);
    my ($cflags) = ($contents =~ /\bTEST_CFLAGS\b(.*)$/m);
    my ($buildcmd) = extract_multiline("TEST_BUILD", $contents, $name);
    my ($builderror) = extract_multiple_multiline("TEST_BUILD_OUTPUT", $contents, $name);
    my ($runerror) = extract_multiple_multiline("TEST_RUN_OUTPUT", $contents, $name);

    return 0 if !$test_h && !$disabled && !$crashes && !defined($conditionstring) && !defined($envstring) && !defined($cflags) && !defined($buildcmd) && !defined($builderror) && !defined($runerror);

    if ($disabled) {
        print "${yellow}SKIP: $name    (disabled by $disabled)$nocolor\n";
        return 0;
    }

    # check test conditions

    my $run = 1;
    my %conditions = readconditions($conditionstring);
    if (! $conditions{LANGUAGE}) {
        # implicit language restriction from file extension
        $conditions{LANGUAGE} = $languages_for_extension{$ext};
    }
    for my $condkey (keys %conditions) {
        my @condvalues = @{$conditions{$condkey}};

        # special case: RUN=0 does not affect build
        if ($condkey eq "RUN"  &&  @condvalues == 1  &&  $condvalues[0] == 0) {
            $run = 0;
            next;
        }

        my $testvalue = $C{$condkey};
        next if !defined($testvalue);
        # testvalue is the configuration being run now
        # condvalues are the allowed values for this test
        
        my $ok = 0;
        for my $condvalue (@condvalues) {

            # special case: objc and objc++
            if ($condkey eq "LANGUAGE") {
                $condvalue = "objective-c" if $condvalue eq "objc";
                $condvalue = "objective-c++" if $condvalue eq "objc++";
            }

            $ok = 1  if ($testvalue eq $condvalue);

            # special case: CC and CXX allow substring matches
            if ($condkey eq "CC"  ||  $condkey eq "CXX") {
                $ok = 1  if ($testvalue =~ /$condvalue/);
            }

            last if $ok;
        }

        if (!$ok) {
            my $plural = (@condvalues > 1) ? "one of: " : "";
            print "SKIP: $name    ($condkey=$testvalue, but test requires $plural", join(' ', @condvalues), ")\n";
            return 0;
        }
    }

    # save some results for build and run phases
    $$CREF{"TEST_$name"} = {
        TEST_BUILD => $buildcmd, 
        TEST_BUILD_OUTPUT => $builderror, 
        TEST_CRASHES => $crashes, 
        TEST_RUN_OUTPUT => $runerror, 
        TEST_CFLAGS => $cflags,
        TEST_ENV => $envstring,
        TEST_RUN => $run, 
    };

    return 1;
}

# Builds a simple test
sub build_simple {
    my %C = %{shift()};
    my $name = shift;
    my %T = %{$C{"TEST_$name"}};
    chdir_verbose "$C{DIR}/$name.build";

    my $ext = $ALL_TESTS{$name};
    my $file = "$DIR/$name.$ext";

    if ($T{TEST_CRASHES}) {
        `echo '$crashcatch' > crashcatch.c`;
        make("$C{COMPILE_C} -dynamiclib -o libcrashcatch.dylib -x c crashcatch.c");
        die "$?" if $?;
    }

    my $cmd = $T{TEST_BUILD} ? eval "return \"$T{TEST_BUILD}\"" : "$C{COMPILE}   $T{TEST_CFLAGS} $file -o $name.out";

    my $output = make($cmd);

    # rdar://10163155
    $output =~ s/ld: warning: could not create compact unwind for [^\n]+: does not use standard frame\n//g;

    my $ok;
    if (my $builderror = $T{TEST_BUILD_OUTPUT}) {
        # check for expected output and ignore $?
        if ($output =~ /$builderror/) {
            $ok = 1;
        } else {
            print "${red}FAIL: /// test '$name' \\\\\\$nocolor\n";
            colorprint $red, $output;
            print "${red}FAIL: \\\\\\ test '$name' ///$nocolor\n";                
            print "${red}FAIL: $name (build output does not match TEST_BUILD_OUTPUT)$nocolor\n";
            $ok = 0;
        }
    } elsif ($?) {
        print "${red}FAIL: /// test '$name' \\\\\\$nocolor\n";
        colorprint $red, $output;
        print "${red}FAIL: \\\\\\ test '$name' ///$nocolor\n";                
        print "${red}FAIL: $name (build failed)$nocolor\n";
        $ok = 0;
    } elsif ($output ne "") {
        print "${red}FAIL: /// test '$name' \\\\\\$nocolor\n";
        colorprint $red, $output;
        print "${red}FAIL: \\\\\\ test '$name' ///$nocolor\n";                
        print "${red}FAIL: $name (unexpected build output)$nocolor\n";
        $ok = 0;
    } else {
        $ok = 1;
    }

    
    if ($ok) {
        foreach my $file (glob("*.out *.dylib *.bundle")) {
            make("dsymutil $file");
        }
    }

    return $ok;
}

# Run a simple test (testname.out, with error checking of stdout and stderr)
sub run_simple {
    my %C = %{shift()};
    my $name = shift;
    my %T = %{$C{"TEST_$name"}};

    if (! $T{TEST_RUN}) {
        print "PASS: $name (build only)\n";
        return 1;
    }

    my $testdir = "$C{DIR}/$name.build";
    chdir_verbose $testdir;

    my $env = "$C{ENV} $T{TEST_ENV}";

    my $output;

    if ($C{ARCH} =~ /^arm/ && `unamep -p` !~ /^arm/) {
        # run on iOS or watchos device

        my $remotedir = "/var/root/objctest/" . basename($C{DIR}) . "/$name.build";

        # Add test dir and libobjc's dir to DYLD_LIBRARY_PATH.
        # Insert libcrashcatch.dylib if necessary.
        $env .= " DYLD_LIBRARY_PATH=$remotedir";
        $env .= ":/var/root/objctest/"  if ($C{TESTLIB} ne $TESTLIBPATH);
        if ($T{TEST_CRASHES}) {
            $env .= " DYLD_INSERT_LIBRARIES=$remotedir/libcrashcatch.dylib";
        }

        my $cmd = "ssh iphone 'cd $remotedir && env $env ./$name.out'";
        $output = make("$cmd");
    }
    elsif ($C{OS} =~ /simulator/) {
        # run locally in an iOS simulator
        # fixme appletvsimulator and watchsimulator
        # fixme SDK
        my $sim = "xcrun -sdk iphonesimulator simctl spawn 'iPhone 6'";

        # Add test dir and libobjc's dir to DYLD_LIBRARY_PATH.
        # Insert libcrashcatch.dylib if necessary.
        $env .= " DYLD_LIBRARY_PATH=$testdir";
        $env .= ":" . dirname($C{TESTLIB})  if ($C{TESTLIB} ne $TESTLIBPATH);
        if ($T{TEST_CRASHES}) {
            $env .= " DYLD_INSERT_LIBRARIES=$testdir/libcrashcatch.dylib";
        }

        my $simenv = "";
        foreach my $keyvalue (split(' ', $env)) {
            $simenv .= "SIMCTL_CHILD_$keyvalue ";
        }
        # Use the full path here so hack_cwd in test.h works.
        $output = make("env $simenv $sim $testdir/$name.out");
    }
    else {
        # run locally

        # Add test dir and libobjc's dir to DYLD_LIBRARY_PATH.
        # Insert libcrashcatch.dylib if necessary.
        $env .= " DYLD_LIBRARY_PATH=$testdir";
        $env .= ":" . dirname($C{TESTLIB})  if ($C{TESTLIB} ne $TESTLIBPATH);
        if ($T{TEST_CRASHES}) {
            $env .= " DYLD_INSERT_LIBRARIES=$testdir/libcrashcatch.dylib";
        }

        $output = make("sh -c '$env ./$name.out'");
    }

    return check_output(\%C, $name, split("\n", $output));
}


my %compiler_memo;
sub find_compiler {
    my ($cc, $toolchain, $sdk_path) = @_;

    # memoize
    my $key = $cc . ':' . $toolchain;
    my $result = $compiler_memo{$key};
    return $result if defined $result;
    
    $result  = make("xcrun -toolchain $toolchain -find $cc 2>/dev/null");

    chomp $result;
    $compiler_memo{$key} = $result;
    return $result;
}

sub make_one_config {
    my $configref = shift;
    my $root = shift;
    my %C = %{$configref};

    # Aliases
    $C{LANGUAGE} = "objective-c"  if $C{LANGUAGE} eq "objc";
    $C{LANGUAGE} = "objective-c++"  if $C{LANGUAGE} eq "objc++";
    
    # Interpret OS version string from command line.
    my ($sdk_arg, $deployment_arg, $run_arg, undef) = split('-', $C{OSVERSION});
    delete $C{OSVERSION};
    my ($os_arg) = ($sdk_arg =~ /^([^\.0-9]+)/);
    $deployment_arg = "default" if !defined($deployment_arg);
    $run_arg = "default" if !defined($run_arg);

    
    die "unknown OS '$os_arg' (expected iphoneos or iphonesimulator or watchos or watchsimulator or macosx)\n" if ($os_arg ne "iphoneos"  &&  $os_arg ne "iphonesimulator"  &&  $os_arg ne "watchos"  &&  $os_arg ne "watchsimulator"  &&  $os_arg ne "macosx");

    $C{OS} = $os_arg;

    if ($os_arg eq "iphoneos" || $os_arg eq "iphonesimulator") {
        $C{TOOLCHAIN} = "ios";
    } elsif ($os_arg eq "watchos" || $os_arg eq "watchsimulator") {
        $C{TOOLCHAIN} = "watchos";
    } elsif ($os_arg eq "macosx") {
        $C{TOOLCHAIN} = "osx";
    } else {
        print "${yellow}WARN: don't know toolchain for OS $C{OS}${nocolor}\n";
        $C{TOOLCHAIN} = "default";
    }
    
    # Look up SDK
    # Try exact match first.
    # Then try lexically-last prefix match (so "macosx" => "macosx10.7internal")
    my @sdks = getsdks();
    if ($VERBOSE) {
        print "note: Installed SDKs: @sdks\n";
    }
    my $exactsdk = undef;
    my $prefixsdk = undef;
    foreach my $sdk (@sdks) {
        $exactsdk = $sdk  if ($sdk eq $sdk_arg);
        $prefixsdk = newersdk($sdk, $prefixsdk)  if ($sdk =~ /^$sdk_arg/);
    }

    my $sdk;
    if ($exactsdk) {
        $sdk = $exactsdk;
    } elsif ($prefixsdk) {
        $sdk = $prefixsdk;
    } else {
        die "unknown SDK '$sdk_arg'\nInstalled SDKs: @sdks\n";
    }

    # Set deployment target and run target.
    # fixme can't enforce version when run_arg eq "default" 
    # because we don't know it yet
    $deployment_arg = versionsuffix($sdk) if $deployment_arg eq "default";
    if ($run_arg ne "default") {
        die "Deployment target '$deployment_arg' is newer than run target '$run_arg'\n"  if $deployment_arg > $run_arg;
    }
    $C{DEPLOYMENT_TARGET} = $deployment_arg;
    $C{RUN_TARGET} = $run_arg;

    # set the config name now, after massaging the language and OS versions, 
    # but before adding other settings
    my $configname = config_name(%C);
    die if ($configname =~ /'/);
    die if ($configname =~ / /);
    ($C{NAME} = $configname) =~ s/~/ /g;
    (my $configdir = $configname) =~ s#/##g;
    $C{DIR} = "$BUILDDIR/$configdir";

    $C{SDK_PATH} = getsdkpath($sdk);

    # Look up test library (possible in root or SDK_PATH)
    
    my $rootarg = $root;
    my $symroot;
    my @sympaths = ( (glob "$root/*~sym")[0], 
                     (glob "$root/BuildRecords/*_install/Symbols")[0], 
                     "$root/Symbols" );
    my @dstpaths = ( (glob "$root/*~dst")[0], 
                     (glob "$root/BuildRecords/*_install/Root")[0], 
                     "$root/Root" );
    for(my $i = 0; $i < scalar(@sympaths); $i++) {
        if (-e $sympaths[$i]  &&  -e $dstpaths[$i]) {
            $symroot = $sympaths[$i];
            $root = $dstpaths[$i];
            last;
        }
    }

    if ($root ne ""  &&  -e "$root$C{SDK_PATH}$TESTLIBPATH") {
        $C{TESTLIB} = "$root$C{SDK_PATH}$TESTLIBPATH";
    } elsif (-e "$root$TESTLIBPATH") {
        $C{TESTLIB} = "$root$TESTLIBPATH";
    } elsif (-e "$root/$TESTLIBNAME") {
        $C{TESTLIB} = "$root/$TESTLIBNAME";
    } else {
        die "No $TESTLIBNAME in root '$rootarg' for sdk '$C{SDK_PATH}'\n"
            # . join("\n", @dstpaths) . "\n"
            ;
    }

    if (-e "$symroot/$TESTLIBNAME.dSYM") {
        $C{TESTDSYM} = "$symroot/$TESTLIBNAME.dSYM";
    }

    if ($VERBOSE) {
        my @uuids = `/usr/bin/dwarfdump -u '$C{TESTLIB}'`;
        while (my $uuid = shift @uuids) {
            print "note: $uuid";
        }
    }

    # Look up compilers
    my $cc = $C{CC};
    my $cxx = cplusplus($C{CC});
    my $swift = swift($C{CC});
    if (! $BUILD) {
        $C{CC} = $cc;
        $C{CXX} = $cxx;
        $C{SWIFT} = $swift
    } else {
        $C{CC} = find_compiler($cc, $C{TOOLCHAIN}, $C{SDK_PATH});
        $C{CXX} = find_compiler($cxx, $C{TOOLCHAIN}, $C{SDK_PATH});
        $C{SWIFT} = find_compiler($swift, $C{TOOLCHAIN}, $C{SDK_PATH});

        die "No compiler '$cc' ('$C{CC}') in toolchain '$C{TOOLCHAIN}'\n" if !-e $C{CC};
        die "No compiler '$cxx' ('$C{CXX}') in toolchain '$C{TOOLCHAIN}'\n" if !-e $C{CXX};
        die "No compiler '$swift' ('$C{SWIFT}') in toolchain '$C{TOOLCHAIN}'\n" if !-e $C{SWIFT};
    }    
    
    # Populate cflags

    # save-temps so dsymutil works so debug info works
    my $cflags = "-I$DIR -W -Wall -Wno-deprecated-declarations -Wshorten-64-to-32 -g -save-temps -Os -arch $C{ARCH} ";
    my $objcflags = "";
    my $swiftflags = "-g ";
    
    $cflags .= " -isysroot '$C{SDK_PATH}'";
    $cflags .= " '-Wl,-syslibroot,$C{SDK_PATH}'";
    $swiftflags .= " -sdk '$C{SDK_PATH}'";
    
    # Set deployment target cflags
    my $target = undef;
    die "No deployment target" if $C{DEPLOYMENT_TARGET} eq "";
    if ($C{OS} eq "iphoneos") {
        $cflags .= " -mios-version-min=$C{DEPLOYMENT_TARGET}";
        $target = "$C{ARCH}-apple-ios$C{DEPLOYMENT_TARGET}";
    }
    elsif ($C{OS} eq "iphonesimulator") {
        $cflags .= " -mios-simulator-version-min=$C{DEPLOYMENT_TARGET}";
        $target = "$C{ARCH}-apple-ios$C{DEPLOYMENT_TARGET}";
    }
    elsif ($C{OS} eq "watchos") {
        $cflags .= " -mwatchos-version-min=$C{DEPLOYMENT_TARGET}";
        $target = "$C{ARCH}-apple-watchos$C{DEPLOYMENT_TARGET}";
    }
    elsif ($C{OS} eq "watchsimulator") {
        $cflags .= " -mwatch-simulator-version-min=$C{DEPLOYMENT_TARGET}";
        $target = "$C{ARCH}-apple-watchos$C{DEPLOYMENT_TARGET}";
    }
    else {
        $cflags .= " -mmacosx-version-min=$C{DEPLOYMENT_TARGET}";
        $target = "$C{ARCH}-apple-macosx$C{DEPLOYMENT_TARGET}";
    }
    $swiftflags .= " -target $target";

    # fixme still necessary?
    if ($C{OS} eq "iphonesimulator"  &&  $C{ARCH} eq "i386") {
        $objcflags .= " -fobjc-abi-version=2 -fobjc-legacy-dispatch";
    }
    
    if ($root ne "") {
        my $library_path = dirname($C{TESTLIB});
        $cflags .= " -L$library_path";
        $cflags .= " -I '$root/usr/include'";
        $cflags .= " -I '$root/usr/local/include'";
        
        if ($C{SDK_PATH} ne "/") {
            $cflags .= " -I '$root$C{SDK_PATH}/usr/include'";
            $cflags .= " -I '$root$C{SDK_PATH}/usr/local/include'";
        }
    }

    if ($C{CC} =~ /clang/) {
        $cflags .= " -Qunused-arguments -fno-caret-diagnostics";
        $cflags .= " -stdlib=$C{STDLIB}"; # fixme -fno-objc-link-runtime"
        $cflags .= " -Wl,-segalign,0x4000 ";
    }

    
    # Populate objcflags
    
    $objcflags .= " -lobjc";
    if ($C{MEM} eq "gc") {
        $objcflags .= " -fobjc-gc";
    }
    elsif ($C{MEM} eq "arc") {
        $objcflags .= " -fobjc-arc";
    }
    elsif ($C{MEM} eq "mrc") {
        # nothing
    }
    else {
        die "unrecognized MEM '$C{MEM}'\n";
    }

    if (supportslibauto($C{OS})) {
        # do this even for non-GC tests
        $objcflags .= " -lauto";
    }
    
    # Populate ENV_PREFIX
    $C{ENV} = "LANG=C MallocScribble=1";
    $C{ENV} .= " VERBOSE=$VERBOSE"  if $VERBOSE;
    if ($root ne "") {
        die "no spaces allowed in root" if dirname($C{TESTLIB}) =~ /\s+/;
    }
    if ($C{GUARDMALLOC}) {
        $ENV{GUARDMALLOC} = "1";  # checked by tests and errcheck.pl
        $C{ENV} .= " DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib";
        if ($C{GUARDMALLOC} eq "before") {
            $C{ENV} .= " MALLOC_PROTECT_BEFORE=1";
        } elsif ($C{GUARDMALLOC} eq "after") {
            # protect after is the default
        } else {
            die "Unknown guard malloc mode '$C{GUARDMALLOC}'\n";
        }
    }

    # Populate compiler commands
    $C{COMPILE_C}   = "env LANG=C '$C{CC}'  $cflags -x c -std=gnu99";
    $C{COMPILE_CXX} = "env LANG=C '$C{CXX}' $cflags -x c++";
    $C{COMPILE_M}   = "env LANG=C '$C{CC}'  $cflags $objcflags -x objective-c -std=gnu99";
    $C{COMPILE_MM}  = "env LANG=C '$C{CXX}' $cflags $objcflags -x objective-c++";
    $C{COMPILE_SWIFT} = "env LANG=C '$C{SWIFT}' $swiftflags";
    
    $C{COMPILE} = $C{COMPILE_C}      if $C{LANGUAGE} eq "c";
    $C{COMPILE} = $C{COMPILE_CXX}    if $C{LANGUAGE} eq "c++";
    $C{COMPILE} = $C{COMPILE_M}      if $C{LANGUAGE} eq "objective-c";
    $C{COMPILE} = $C{COMPILE_MM}     if $C{LANGUAGE} eq "objective-c++";
    $C{COMPILE} = $C{COMPILE_SWIFT}  if $C{LANGUAGE} eq "swift";
    die "unknown language '$C{LANGUAGE}'\n" if !defined $C{COMPILE};

    ($C{COMPILE_NOMEM} = $C{COMPILE}) =~ s/ -fobjc-(?:gc|arc)\S*//g;
    ($C{COMPILE_NOLINK} = $C{COMPILE}) =~ s/ '?-(?:Wl,|l)\S*//g;
    ($C{COMPILE_NOLINK_NOMEM} = $C{COMPILE_NOMEM}) =~ s/ '?-(?:Wl,|l)\S*//g;


    # Reject some self-inconsistent configurations
    if ($C{MEM} !~ /^(mrc|arc|gc)$/) {
        die "unknown MEM=$C{MEM} (expected one of mrc arc gc)\n";
    }

    if ($C{MEM} eq "gc"  &&  $C{OS} !~ /^macosx/) {
        print "note: skipping configuration $C{NAME}\n";
        print "note:   because OS=$C{OS} does not support MEM=$C{MEM}\n";
        return 0;
    }
    if ($C{MEM} eq "gc"  &&  $C{ARCH} eq "x86_64h") {
        print "note: skipping configuration $C{NAME}\n";
        print "note:   because ARCH=$C{ARCH} does not support MEM=$C{MEM}\n";
        return 0;
    }
    if ($C{MEM} eq "arc"  &&  $C{OS} =~ /^macosx/  &&  $C{ARCH} eq "i386") {
        print "note: skipping configuration $C{NAME}\n";
        print "note:   because 32-bit Mac does not support MEM=$C{MEM}\n";
        return 0;
    }
    if ($C{MEM} eq "arc"  &&  $C{CC} !~ /clang/) {
        print "note: skipping configuration $C{NAME}\n";
        print "note:   because CC=$C{CC} does not support MEM=$C{MEM}\n";
        return 0;
    }

    if ($C{STDLIB} ne "libstdc++"  &&  $C{CC} !~ /clang/) {
        print "note: skipping configuration $C{NAME}\n";
        print "note:   because CC=$C{CC} does not support STDLIB=$C{STDLIB}\n";
        return 0;
    }

    # fixme 
    if ($C{LANGUAGE} eq "swift"  &&  $C{ARCH} =~ /^arm/) {
        print "note: skipping configuration $C{NAME}\n";
        print "note:   because ARCH=$C{ARCH} does not support LANGUAGE=SWIFT\n";
        return 0;
    }

    # fixme unimplemented run targets
    if ($C{RUN_TARGET} ne "default" &&  $C{OS} !~ /simulator/) {
        print "${yellow}WARN: skipping configuration $C{NAME}${nocolor}\n";
        print "${yellow}WARN:   because OS=$C{OS} does not yet implement RUN_TARGET=$C{RUN_TARGET}${nocolor}\n";
    }

    %$configref = %C;
}    

sub make_configs {
    my ($root, %args) = @_;

    my @results = ({});  # start with one empty config

    for my $key (keys %args) {
        my @newresults;
        my @values = @{$args{$key}};
        for my $configref (@results) {
            my %config = %{$configref};
            for my $value (@values) {
                my %newconfig = %config;
                $newconfig{$key} = $value;
                push @newresults, \%newconfig;
            }
        }
        @results = @newresults;
    }

    my @newresults;
    for my $configref(@results) {
        if (make_one_config($configref, $root)) {
            push @newresults, $configref;
        }
    }

    return @newresults;
}

sub config_name {
    my %config = @_;
    my $name = "";
    for my $key (sort keys %config) {
        $name .= '~'  if $name ne "";
        $name .= "$key=$config{$key}";
    }
    return $name;
}

sub run_one_config {
    my %C = %{shift()};
    my @tests = @_;

    # Build and run
    my $testcount = 0;
    my $failcount = 0;

    my @gathertests;
    foreach my $test (@tests) {
        if ($VERBOSE) {
            print "\nGATHER $test\n";
        }

        if ($ALL_TESTS{$test}) {
            gather_simple(\%C, $test) || next;  # not pass, not fail
            push @gathertests, $test;
        } else {
            die "No test named '$test'\n";
        }
    }

    my @builttests;
    if (!$BUILD) {
        @builttests = @gathertests;
        $testcount = scalar(@gathertests);
    } else {
        my $configdir = $C{DIR};
        print $configdir, "\n"  if $VERBOSE;
        mkdir $configdir  || die;

        foreach my $test (@gathertests) {
            if ($VERBOSE) {
                print "\nBUILD $test\n";
            }
            mkdir "$configdir/$test.build"  || die;
            
            if ($ALL_TESTS{$test}) {
                $testcount++;
                if (!build_simple(\%C, $test)) {
                    $failcount++;
                } else {
                    push @builttests, $test;
                }
            } else {
                die "No test named '$test'\n";
            }
        }
    }
    
    if (!$RUN  ||  !scalar(@builttests)) {
        # nothing to do
    }
    else {
        if ($C{ARCH} =~ /^arm/ && `unamep -p` !~ /^arm/) {
            # upload all tests to iOS device
            make("RSYNC_PASSWORD=alpine rsync -av $C{DIR} rsync://root\@localhost:10873/root/var/root/objctest/");
            die "Couldn't rsync tests to device\n" if ($?);

            # upload library to iOS device
            if ($C{TESTLIB} ne $TESTLIBPATH) {
                make("RSYNC_PASSWORD=alpine rsync -av $C{TESTLIB} rsync://root\@localhost:10873/root/var/root/objctest/");
                die "Couldn't rsync $C{TESTLIB} to device\n" if ($?);
                make("RSYNC_PASSWORD=alpine rsync -av $C{TESTDSYM} rsync://root\@localhost:10873/root/var/root/objctest/");
            }
        }

        foreach my $test (@builttests) {
            print "\nRUN $test\n"  if ($VERBOSE);
            
            if ($ALL_TESTS{$test})
            {
                if (!run_simple(\%C, $test)) {
                    $failcount++;
                }
            } else {
                die "No test named '$test'\n";
            }
        }
    }
    
    return ($testcount, $failcount);
}



# Return value if set by "$argname=value" on the command line
# Return $default if not set.
sub getargs {
    my ($argname, $default) = @_;

    foreach my $arg (@ARGV) {
        my ($value) = ($arg =~ /^$argname=(.+)$/);
        return [split ',', $value] if defined $value;
    }

    return [split ',', $default];
}

# Return 1 or 0 if set by "$argname=1" or "$argname=0" on the 
# command line. Return $default if not set.
sub getbools {
    my ($argname, $default) = @_;

    my @values = @{getargs($argname, $default)};
    return [( map { ($_ eq "0") ? 0 : 1 } @values )];
}

# Return an integer if set by "$argname=value" on the 
# command line. Return $default if not set.
sub getints {
    my ($argname, $default) = @_;

    my @values = @{getargs($argname, $default)};
    return [( map { int($_) } @values )];
}

sub getarg {
    my ($argname, $default) = @_;
    my @values = @{getargs($argname, $default)};
    die "Only one value allowed for $argname\n"  if @values > 1;
    return $values[0];
}

sub getbool {
    my ($argname, $default) = @_;
    my @values = @{getbools($argname, $default)};
    die "Only one value allowed for $argname\n"  if @values > 1;
    return $values[0];
}

sub getint {
    my ($argname, $default) = @_;
    my @values = @{getints($argname, $default)};
    die "Only one value allowed for $argname\n"  if @values > 1;
    return $values[0];
}


# main
my %args;


my $default_arch = (`/usr/sbin/sysctl hw.optional.x86_64` eq "hw.optional.x86_64: 1\n") ? "x86_64" : "i386";
$args{ARCH} = getargs("ARCH", 0);
$args{ARCH} = getargs("ARCHS", $default_arch)  if !@{$args{ARCH}}[0];

$args{OSVERSION} = getargs("OS", "macosx-default-default");

$args{MEM} = getargs("MEM", "mrc");
$args{LANGUAGE} = [ map { lc($_) } @{getargs("LANGUAGE", "objective-c,swift")} ];
$args{STDLIB} = getargs("STDLIB", "libc++");

$args{CC} = getargs("CC", "clang");

{
    my $guardmalloc = getargs("GUARDMALLOC", 0);    
    # GUARDMALLOC=1 is the same as GUARDMALLOC=before,after
    my @guardmalloc2 = ();
    for my $arg (@$guardmalloc) {
        if ($arg == 1) { push @guardmalloc2, "before"; 
                         push @guardmalloc2, "after"; }
        else { push @guardmalloc2, $arg }
    }
    $args{GUARDMALLOC} = \@guardmalloc2;
}

$BUILD = getbool("BUILD", 1);
$RUN = getbool("RUN", 1);
$VERBOSE = getint("VERBOSE", 0);

my $root = getarg("ROOT", "");
$root =~ s#/*$##;

my @tests = gettests();

print "note: -----\n";
print "note: testing root '$root'\n";

my @configs = make_configs($root, %args);

print "note: -----\n";
print "note: testing ", scalar(@configs), " configurations:\n";
for my $configref (@configs) {
    my $configname = $$configref{NAME};
    print "note: configuration $configname\n";
}

if ($BUILD) {
    `rm -rf '$BUILDDIR'`;
    mkdir "$BUILDDIR" || die;
}

my $failed = 0;

my $testconfigs = @configs;
my $failconfigs = 0;
my $testcount = 0;
my $failcount = 0;
for my $configref (@configs) {
    my $configname = $$configref{NAME};
    print "note: -----\n";
    print "note: \nnote: $configname\nnote: \n";

    (my $t, my $f) = eval { run_one_config($configref, @tests); };
    if ($@) {
        chomp $@;
        print "${red}FAIL: $configname${nocolor}\n";
        print "${red}FAIL: $@${nocolor}\n";
        $failconfigs++;
    } else {
        my $color = ($f ? $red : "");
        print "note:\n";
        print "${color}note: $configname$nocolor\n";
        print "${color}note: $t tests, $f failures$nocolor\n";
        $testcount += $t;
        $failcount += $f;
        $failconfigs++ if ($f);
    }
}

print "note: -----\n";
my $color = ($failconfigs ? $red : "");
print "${color}note: $testconfigs configurations, $failconfigs with failures$nocolor\n";
print "${color}note: $testcount tests, $failcount failures$nocolor\n";

$failed = ($failconfigs ? 1 : 0);

exit ($failed ? 1 : 0);
