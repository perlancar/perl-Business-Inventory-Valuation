package Business::Inventory::Valuation;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless {}, $class;

    die "Please specify method" unless $args{method};
    die "Invalid method, please choose LIFO/FIFO"
        unless $args{method} =~ /\A(LIFO|FIFO)\z/;
    $self->{method} = delete $args{method};

    $self->{allow_negative_inventory} = delete $args{allow_negative_inventory};

    keys(%args) and die "Unknown argument(s): ".join(", ", keys %args);

    $self->{_inventory} = [];
    $self->{_units} = 0;
    $self->{_average_purchase_price} = undef;

    $self;
}

sub buy {
    my ($self, $units, $unit_price) = @_;

    # sanity checks
    die "Units must be > 0" unless $units > 0;
    die "Unit price must be >= 0" unless $unit_price >= 0;

    if (@{ $self->{_inventory} } && $self->{_inventory}[-1][1] == $unit_price) {
        my $old_units = $self->{_units};
        $self->{_inventory}[-1][0] += $units;
        $self->{_units} += $units;
        $self->{_average_purchase_price} = (
            $old_units * $self->{_average_purchase_price} +
                $units * $unit_price) / $self->{_units};
    } else {
        push @{ $self->{_inventory} }, [$units, $unit_price];

        if (@{ $self->{_inventory} } == 1) {
            $self->{_units} = $units;
            $self->{_average_purchase_price} = $unit_price;
        } else {
            my $old_units = $self->{_units};
            $self->{_units}+= $units;
            $self->{_average_purchase_price} = (
                $old_units * $self->{_average_purchase_price} +
                    $units * $unit_price) / $self->{_units};
        }
    }
}

sub sell {
    my ($self, $units, $unit_price) = @_;

    # sanity checks
    die "Units must be > 0" unless $units > 0;
    die "Unit price must be >= 0" unless $unit_price >= 0;

    my $profit = 0;

   if ($self->{_units} < $units) {
        if ($self->{allow_negative_inventory}) {
            $units = $self->{_units};
        } else {
            die "Attempted to oversell ($units, while inventory only has ".
                "$self->{_units})";
        }
    }

    my $remaining = $units;
    my $orig_average_purchase_price = $self->{_average_purchase_price};

    # due to rounding error, _units and _inventory might disagree for a bit
    while ($self->{_units} > 0 && @{ $self->{_inventory} } && $remaining > 0) {
        my $item;
        if ($self->{method} eq 'LIFO') {
            $item = $self->{_inventory}[-1];
        } else {
            $item = $self->{_inventory}[0];
        }

        if ($item->[0] > $remaining) {
            # inventory item is not used up
            my $old_units = $self->{_units};
            $item->[0] -= $remaining;
            $self->{_units} -= $remaining;
            if ($self->{_units} == 0) {
                undef $self->{_average_purchase_price};
            } else {
                $self->{_average_purchase_price} = (
                    $old_units * $self->{_average_purchase_price} -
                        $remaining * $item->[1]) / $self->{_units};
            }
            $profit += $remaining * ($unit_price - $item->[1]);
            $remaining = 0;
            goto RETURN;
        } else {
            # inventory item is used up, remove from inventory
            if ($self->{method} eq 'LIFO') {
                pop @{ $self->{_inventory} };
            } else {
                shift @{ $self->{_inventory} };
            }
            $remaining -= $item->[0];
            my $old_units = $self->{_units};
            $self->{_units} -= $item->[0];
            $profit += $item->[0] * ($unit_price - $item->[1]);
            if ($self->{_units} == 0) {
                undef $self->{_average_purchase_price};
            } else {
                $self->{_average_purchase_price} = (
                    $old_units * $self->{_average_purchase_price} -
                        $item->[0] * $item->[1]) / $self->{_units};
            }
        }
    }

  RETURN:
    my @return;
    if (defined $orig_average_purchase_price) {
        push @return, $units *
            ($unit_price - $orig_average_purchase_price);
    } else {
        push @return, undef;
    }
    push @return, $profit;
    @return;
}

sub inventory {
    my $self = shift;
    @{ $self->{_inventory} };
}

sub units {
    my $self = shift;
    $self->{_units};
}

sub average_purchase_price {
    my $self = shift;
    $self->{_average_purchase_price};
}


1;
# ABSTRACT: Calculate inventory value/unit price (using LIFO or FIFO)

=head1 SYNOPSIS

 use Business::Inventory::Valuation;

 my $biv = Business::Inventory::Valuation->new(
     method                   => 'LIFO', # required. choose LIFO/FIFO
     #allow_negative_inventory => 0,     # optional, default 0
 );

 my @inv;

 # buy: 100 units @1500
 $biv->buy(100, 1500);
 @inv = $biv->inventory;              # => ([100, 1500])
 say $biv->units;                     # 100
 say $biv->average_purchase_price;    # 1500

 # buy more: 150 units @1600
 $biv->buy(150, 1600);
 @inv = $biv->inventory;              # => ([100, 1500], [150, 1600])
 say $biv->units;                     # 250
 say $biv->average_purchase_price;    # 1560

 # sell: 50 units @1700. with LIFO method, the most recently purchased units are sold first.
 $biv->sell( 25, 1700);               # returns two versions of realized profit: (7000, 5000)
 @inv = $biv->inventory;              # => ([100, 1500], [100, 1600])
 say $biv->units;                     # 200
 say $biv->average_purchase_price;    # 1550

 # buy: 200 units @1500
 $biv->buy(200, 1500);
 @inv = $biv->inventory;              # => ([100, 1500], [100, 1600], [200, 1500])
 say $biv->units;                     # 400
 say $biv->average_purchase_price;    # 1550

 # sell: 350 units @1800
 $biv->sell(350, 1800);               # returns two versions of realized profit: (96250, 95000)
 @inv = $biv->inventory;              # => ([50, 1500])
 say $biv->units;                     # 50
 say $biv->average_purchase_price;    # 1500
 ($units, $avgprice) = $biv->summary; # => (50, 1500)

 # sell: 60 units @1700
 $biv->sell(60, 1800);                # dies! tried to oversell more than available in inventory.

With FIFO method, the most anciently purchased units are sold first:

 my $biv = Business::Inventory::Valuation->new(method => 'FIFO');
 $biv->buy(100, 1500);
 $biv->buy(150, 1600);
 $biv->sell( 25, 1700);               # returns two versions of realized profit: (7000, 10000)
 @inv = $biv->inventory;              # => ([50, 1500], [150, 1600])
 say $biv->units;                     # 200
 say $biv->average_purchase_price;    # 1575

Overselling is allowed when C<allow_negative_inventory> is set to true. Amount
sold is set to the available inventory and inventory becomes empty:

 my $biv = Business::Inventory::Valuation->new(
     method => 'LIFO',
     allow_negative_inventory => 1,   # optional, default 0
 );
 $biv->buy(100, 1500);
 $biv->buy(150, 1600);
 $biv->sell(300, 1700);               # returns two versions of realized profit: (35000, 35000)
 @inv = $biv->inventory;              # => ()
 say $biv->units;                     # 0
 say $biv->average_purchase_price;    # undef


=head1 DESCRIPTION

This module can be used if you want to calculate average purchase price from a
series of purchases each with different prices (like when buying stocks or
cryptocurrencies) or want to value your inventory using LIFO/FIFO method.

Keywords: average purchase price, inventory valuation, FIFO, LIFO.


=head1 METHODS

=head2 new

Usage: Business::Inventory::Valuation->new(%args) => obj

Known arguments (C<*> denotes required argument):

=over

=item * method* => str ("LIFO"|"FIFO")

=item * allow_negative_inventory => bool (default: 0)

By default, when you try to C<sell()> more amount than you have bought, the
method will die. When this argument is set to true, the method will not die but
will simply ignore then excess amount sold (see L</"sell"> for more details).

=back

=head2 buy

Usage: $biv->buy($units, $unit_price) => num

Add units to inventory. Will return average purchase price, which is calculated
as the weighted average from all purchases.

=head2 sell

Usage: $biv->sell($units, $unit_price) => ($profit1, $profit2)

Take units from inventory. If method is FIFO, will take the units according to
the order of purchase (units bought earlier will be taken first). If method is
LIFO, will take the units according to the reverse order of purchase (units
bought later will be taken first).

Will die if C<$units> exceeds the number of units in inventory (overselling),
unless when C<allow_negative_inventory> constructor argument is set to true (see
L</"new">) which will just take the inventory up to the amount of inventory and
set the inventory to zero.

C<$unit_price> is the unit selling price.

Will return a list containing two versions of realized profits. The first
element is profit calculated using average purchase price: C<$unit_price> -
I<average-purchase-price> x I<units-sold>. The second element is profit
calculated by the actual purchase price of the taken units.

=head2 units

Usage: $biv->units => num

Return the current number of units in the inventory.

If you want to know each number of units bought at different prices, use
L</"inventory">.

=head2 average_purchase_price

Usage: $biv->average_purchase_price => num

Return the average purchase price, which is calculated by weighted average.

If there is no inventory, will return undef.

=head2 inventory

Usage: $biv->inventory => @ary

Return the current inventory, which is a list of C<[units, price]> arrays. For
example if you buy 500 units @10 then buy another 1000 units @12.5,
C<inventory()> will return: C<< ([500, 10], [1000, 12.5]) >>.


=head1 SEE ALSO
