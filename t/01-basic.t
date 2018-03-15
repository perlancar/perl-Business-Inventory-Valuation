#!perl

use 5.010001;
use strict;
use warnings;
use Test::Exception;
use Test::More 0.98;

use Business::Inventory::Valuation;

subtest "sanity" => sub {
    dies_ok { Business::Inventory::Valuation->new() } "no required argument";
    dies_ok { Business::Inventory::Valuation->new(method => "foo") } "invalid value of method";
    dies_ok { Business::Inventory::Valuation->new(method => "LIFO", foo=>1) } "unknown argument";

    my $biv = Business::Inventory::Valuation->new(method => "LIFO", allow_negative_inventory=>0);
    dies_ok { $biv->buy(-1, 100) } 'negative buy amount';

    $biv->buy(10, 100);

    dies_ok { $biv->sell(-1, 100) } 'negative sell amount';
};

subtest "method=LIFO" => sub {
    my $biv = Business::Inventory::Valuation->new(method => 'LIFO');

    is_deeply([$biv->inventory], []);
    is_deeply($biv->units, 0);
    is_deeply($biv->average_purchase_price, undef);

    # buy: 100 units @1500
    $biv->buy(100, 1500);
    is_deeply([$biv->inventory], [[100, 1500]]);
    is_deeply($biv->units, 100);
    is_deeply($biv->average_purchase_price, 1500);

    # buy more: 150 units @1600
    $biv->buy(150, 1600);
    is_deeply([$biv->inventory], [[100, 1500], [150, 1600]]);
    is_deeply($biv->units, 250);
    is_deeply($biv->average_purchase_price, 1560);

    # sell: 50 units @1700
    is_deeply([$biv->sell( 50, 1700)], [7000, 5000]);
    is_deeply([$biv->inventory], [[100, 1500], [100, 1600]]);
    is_deeply($biv->units, 200);
    is_deeply($biv->average_purchase_price, 1550);

    # buy: 200 units @1500
    $biv->buy(200, 1500);
    is_deeply([$biv->inventory], [[100, 1500], [100, 1600], [200, 1500]]);
    is_deeply($biv->units, 400);
    is_deeply($biv->average_purchase_price, 1525);

    # sell: 350 units @1800
    is_deeply([$biv->sell(350, 1800)], [96250, 95000]);
    is_deeply([$biv->inventory], [[50, 1500]]);
    is_deeply($biv->units, 50);
    is_deeply($biv->average_purchase_price, 1500);

    # oversell: 60 units @1700
    dies_ok { $biv->sell(60, 1800) };

    # sell all
    is_deeply([$biv->sell(50, 1750)], [12500, 12500]);
    is_deeply([$biv->inventory], []);
    is_deeply($biv->units, 0);
    is_deeply($biv->average_purchase_price, undef);
};

subtest "method=FIFO" => sub {
    my $biv = Business::Inventory::Valuation->new(method => 'FIFO');

    is_deeply([$biv->inventory], []);
    is_deeply($biv->units, 0);
    is_deeply($biv->average_purchase_price, undef);

    # buy: 100 units @1500
    $biv->buy(100, 1500);
    is_deeply([$biv->inventory], [[100, 1500]]);
    is_deeply($biv->units, 100);
    is_deeply($biv->average_purchase_price, 1500);

    # buy more: 150 units @1600
    $biv->buy(150, 1600);
    is_deeply([$biv->inventory], [[100, 1500], [150, 1600]]);
    is_deeply($biv->units, 250);
    is_deeply($biv->average_purchase_price, 1560);

    # sell: 50 units @1700
    is_deeply([$biv->sell( 50, 1700)], [7000, 10000]);
    is_deeply([$biv->inventory], [[50, 1500], [150, 1600]]);
    is_deeply($biv->units, 200);
    is_deeply($biv->average_purchase_price, 1575);

    # buy: 200 units @1500
    $biv->buy(200, 1800);
    is_deeply([$biv->inventory], [[50, 1500], [150, 1600], [200, 1800]]);
    is_deeply($biv->units, 400);
    is_deeply($biv->average_purchase_price, 1687.5);

    # sell: 350 units @1800
    is_deeply([$biv->sell(350, 1900)], [74375, 80000]);
    is_deeply([$biv->inventory], [[50, 1800]]);
    is_deeply($biv->units, 50);
    is_deeply($biv->average_purchase_price, 1800);

    # sell: 60 units @1700
    dies_ok { $biv->sell(60, 1800) };
};

subtest "allow_negative_inventory=1" => sub {
    my $biv = Business::Inventory::Valuation->new(
        method => 'LIFO',
        allow_negative_inventory => 1,
    );

    $biv->buy(100, 1500);
    is_deeply([$biv->sell(150, 1600)], [10000, 10000]);
    is_deeply($biv->units, 0);
    is_deeply($biv->average_purchase_price, undef);
};

subtest "optimization: subsequent buy at the same price will be merged" => sub {
    my $biv = Business::Inventory::Valuation->new(method => 'LIFO');
    $biv->buy(100, 1500);
    is_deeply([$biv->inventory], [[100,1500]]);
    $biv->buy(200, 1500);
    is_deeply([$biv->inventory], [[300,1500]]);
};

DONE_TESTING:
done_testing;
