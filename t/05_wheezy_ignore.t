# -*- mode: cperl; -*-
use Test::More;

BEGIN{
    $ENV{DEBBUGS_CONFIG_FILE}="t/test_spool_debbugs_config";
}

use Debbugs::Config qw(%config);
use Data::Dumper;

use_ok('Debbugs::Config');

use_ok('bugcfg');
use_ok('scanlib');

# scan all bugs; this should keep everything appropriately
scanlib::scanspool();
ok(exists $scanlib::bugs{710069},'710069 is kept from scanlib');
ok(exists $scanlib::bugs{710357},'710357 is kept from scanlib');
use Data::Dumper;
ok(!scanlib::check_worry_stable($scanlib::bugs{710069}),'710069 does not concern stable');
# this bug would concern testing, but the package isn't in testing...
# ok(scanlib::check_worry($scanlib::bugs{710069}),'710069 does concerns testing');
ok(scanlib::check_worry_unstable($scanlib::bugs{710069}),'710069 concerns unstable');
ok(!scanlib::check_worry_stable($scanlib::bugs{710357}),'710357 does not concern stable');
ok(!scanlib::check_worry($scanlib::bugs{710357}),'710357 does not concern testing');
ok(!scanlib::check_worry_unstable($scanlib::bugs{710357}),'710357 does not concern unstable');

# OK; things seem to work properly here, so why are these being counted?
ok(scanlib::get_taginfo($scanlib::bugs{710357}) =~ qr/I$/,'710357 has an I taginfo' );
ok(scanlib::get_taginfo($scanlib::bugs{710069}) =~ qr/I$/,'710069 has an I taginfo' );

# done testing
done_testing();
