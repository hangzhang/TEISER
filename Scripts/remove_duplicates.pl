use lib "$ENV{TEISERDIR}/Scripts";


use Sets;
use Table;
use strict;
use Fasta;
use strict;
use Getopt::Long ;
use Data::Dumper; 

my $fastafile       = undef ;
my $expfile         = undef ;
my $outfile         = undef ;
my $dupfile         = undef ;
my $quantized       = 1 ;
my $ebins           = undef ;
my $divbins         = 50.0 ;
my $mbins           = 2 ;
my $seed            = 2324 ;

GetOptions ('expfile=s'              => \$expfile,
	    'fastafile=s'            => \$fastafile,
	    'outfile=s'              => \$outfile,
	    'dupfile=s'              => \$dupfile,
	    'quantized=i'            => \$quantized,
	    'ebins=i'                => \$ebins,
	    'divbins=i'              => \$divbins,
	    'mbins=i'                => \$mbins,) ;

if ($dupfile == undef){
    $dupfile = "$fastafile.homologies";
    print "Assuming homology file is $dupfile.\n";
}
if (! -e $dupfile) {
  die "$dupfile does not exist.\n";
}
srand($seed);

if ($quantized == 1) {
  print "Processing expression data as quantized.\n";
} else {
  print "Processing expression data as continuous.\n";
}

my %dups = ();
open IN, $dupfile or die "cannot open $dupfile\n";
my $l = <IN>;
while (my $l = <IN>) {
  chomp $l;
  my @a = split /\t/, $l;
  
  my $n = shift @a;
  
  foreach my $g (@a) {
    $dups{$n}{$g} = 1;
    $dups{$g}{$n} = 1;
  }
}
close IN;

open OUT, ">$outfile";

my %expgenes = ();
open IN, $expfile;
my $l = <IN>;
print OUT $l;

while (my $l = <IN>) {
  chomp $l;
  my @a = split /\t/, $l;
  $expgenes{ $a[0] } = $a[1];
}
close IN;

my $fa = Fasta->new;
$fa->setFile($fastafile);

my %expgenes_good = ();
while (my $a_ref = $fa->nextSeq()) {
  my ($n, $s) = @$a_ref;
  
  if (defined($expgenes{ $n })) {
    $expgenes_good{ $n } = $expgenes{ $n };
  } 
  
}

if ($quantized == 1) {  
  my $a_ref_fil = remove_dups_from_quantized_vector(\%expgenes_good, \%dups);
  my $cnt = 0;
  foreach my $r (@$a_ref_fil) {
    print OUT "$r\t$expgenes_good{$r}\n";
    $cnt ++;
  }
  
  printf "Retained $cnt genes\n";
  

} else {

  #
  # do a loop while there are differences between iterations
  #

  my $a_ref_fil               = [];
  my $a_ref_fil_new           = [];
  my $h_ref_expgenes_good     = \%expgenes_good;
  my $h_ref_expgenes_good_new = undef;

  my $n_init                  = scalar( keys(%$h_ref_expgenes_good) );

  my $cnt = 1;
  while (1) {

    print "iter $cnt\t"; $cnt ++;

    my $N = scalar( keys(%$h_ref_expgenes_good) );
    
    # how many bins ?

    if (!defined($ebins)) {
      $ebins = $N / ($divbins * $mbins ); 
    }
    
    my @VAL = ();
    my @GEN = ();
    foreach my $g (sort(keys(%$h_ref_expgenes_good))) {
      push @VAL, $h_ref_expgenes_good->{$g};
      push @GEN, $g;
    }
    
    my $vq = Quantize(\@VAL, $ebins);
    
    my %expgenes_good_q = ();
    for (my $i=0; $i<$N; $i++) {
      $expgenes_good_q{ $GEN[$i] } =  $vq->[$i];
    }
    
    $a_ref_fil_new = remove_dups_from_quantized_vector(\%expgenes_good_q, \%dups);
    my $a_ref_ov   = Sets::getOverlapSet($a_ref_fil, $a_ref_fil_new);
    
    print "- ". scalar(@VAL) . " to " . scalar(@$a_ref_fil_new) . "\n";
    
    #
    # if the end set is the same as the start set, stop
    #
    if ((scalar(@$a_ref_ov) == scalar(@$a_ref_fil_new)) && (scalar(@$a_ref_ov) == scalar(@$a_ref_fil))) {

      last;

    } else {
      
      $a_ref_fil = $a_ref_fil_new;

      my %h1 = ();
      $h_ref_expgenes_good_new = \%h1;
      foreach my $r (@$a_ref_fil) {
	$h_ref_expgenes_good_new->{$r} = $h_ref_expgenes_good->{ $r };
      }
      $h_ref_expgenes_good = $h_ref_expgenes_good_new;
      
    }
   
  }

  my $n_end = @$a_ref_fil;

  print "Removed " . ($n_init - $n_end) . " genes.\n";
  
  foreach my $r (@$a_ref_fil) {
    print OUT "$r\t$expgenes_good{$r}\n";
  }
  
}


close OUT;


sub Quantize{ 

  my ($v, $D) = @_;
    
  my $n = scalar( @$v );
  
  my $binsize = int( 0.5 + $n / $D);

  my @fi = ();
  for (my $i=0; $i<$n; $i++) {
    $fi[$i]->[0] = $i;
    $fi[$i]->[1] = $v->[$i];
  }
  
  @fi = sort { $a->[1] <=> $b->[1] } @fi;

  my $qv = [];

  for (my $i=0; $i<$D; $i++) {
    my $j        = $i * $binsize;

    while (( $j < ($i+1)*$binsize) && ($j < $n)) {
      $qv->[ $fi[$j]->[0] ] = $i;
      $j ++;
    }
  }

  return $qv;
}

sub remove_dups_from_quantized_vector {
  
  my ($h_ref_expgenes_good, $h_ref_dups, $h_ref_exp) = @_;
  
  
  my @STUFF = ();

  my %CLUSTER = ();
  
  foreach my $g (sort(keys(%{ $h_ref_expgenes_good }))) {
    push @{ $CLUSTER{ $h_ref_expgenes_good->{ $g } } }, $g;
  }

  foreach my $c (sort(keys(%CLUSTER))) {
    my $m = scalar ( @{ $CLUSTER{ $c }} );
    my %OUT = ();
    for (my $i=0; $i<$m-1; $i++) {
      for (my $j=$i+1; $j<$m; $j++) {
	if (defined($h_ref_dups->{ $CLUSTER{ $c }->[$i] }{ $CLUSTER{ $c }->[$j] })) {
	  
	  #$OUT{ $CLUSTER{ $c }->[$i] } = 1;
	  #$OUT{ $CLUSTER{ $c }->[$j] } = 1;

	  if (defined($OUT{ $CLUSTER{ $c }->[$i] }) || defined($OUT{ $CLUSTER{ $c }->[$j] })) {
	    # do nothing, a gene has already been removed
	  } else {
	    my $rn = rand;
	    
	    if ($rn > 0.5) {
	      $OUT{ $CLUSTER{ $c }->[$i] } = 1;
	    } else {
	      $OUT{ $CLUSTER{ $c }->[$j] } = 1;
	    }
	  }
	}
      } 
    } 
    
    foreach my $g ( @{ $CLUSTER{ $c }} ) {
      
      if (!defined($OUT{$g})) {
	push @STUFF, $g;
      }

    }
    
  }

  return \@STUFF;
  
}
