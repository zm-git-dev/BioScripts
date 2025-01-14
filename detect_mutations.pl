#!/usr/bin/perl -w
#
#   detect_mutations.pl -- Screen out candidate mutation sites.
#                          
#
#   Author: Nowind
#   Created: 2012-05-31
#   Updated: 2019-07-30
#   Version: 1.5.0
#
#   Change logs:
#   Version 1.0.0 14/05/15: The initial version.
#   Version 1.0.1 14/05/16: Add support for indel mutations.
#   Version 1.0.2 14/05/26: Add option "--no-ref-mut".
#   Version 1.0.3 14/06/06: Fill AD field with 0 if AD field is missing; set default library criteria to 0.
#   Version 1.0.4 14/06/17: Add option "--max-cmp-miss".
#   Version 1.1.0 14/11/26: Add several new options; rearrange all previous options.
#   Version 1.1.1 14/11/27: Update "--controls" option and one can use this option to filter mutation calls without 
#                           valid control calls.
#   Version 1.1.2 14/12/01: Bug fixed in output vcf headers.
#   Version 1.1.3 14/12/02: Add option "--max-shared-freq" to generate mutation loci shared among several samples
#   Version 1.1.4 14/12/03: Add "MAR" in INFO field; set sample to missing if total depth is zero.
#   Version 1.2.0 15/01/18: Bug fixed: (1) no quality field available; (2) AD fields not updated after merge vcf files.
#   Version 1.2.1 15/01/19: Add support for vcf file generated from Platypus.
#   Version 1.2.2 15/07/01: Comment some debug codes which could possible cause premature stop of script.
#   Version 1.2.3 15/09/23: Output sorted sample ids.
#   Version 1.3.0 15/09/26: Update some option comments; add support for screen group-specific mutations.
#   Version 1.3.1 15/09/29: Bug fixed where group info missed in some loci.
#   Version 1.3.2 15/10/07: Add support for depth and strand bias check of shared mutations.
#   Version 1.3.3 15/11/04: Bug fixed: FILTER field not proper assigned in multiple-allelic loci.
#   Version 1.3.4 18/11/02: Update some option descriptions.
#   Version 1.4.0 19/05/31: Updated: add support for vcf file generated from Delly; add option "--append-info" to preserve
#                           original INFO field.
#   Version 1.5.0 19/07/30: Updated: add option "--min-split-cnt" to filter vcf file generated from Manta; update several
##                          comments.

use strict;

use Data::Dumper;
use Getopt::Long;
use File::Find::Rule;
use File::Basename;

use MyPerl::FileIO qw(:all);
use MyPerl::Vcf qw(:all);

######################## Main ########################
my $CMDLINE = "perl $0 @ARGV";
my $VERSION = '1.5.0';
my $HEADER  = "##$CMDLINE\n##Version: $VERSION\n";
my $SOURCE  = (scalar localtime()) . " Version: $VERSION";

my %options = ();
   $options{max_cmp_depth}  = 1;
   $options{help} = ($CMDLINE =~ /\-help/) ? 0 : 1;
GetOptions(
            "vcf=s"              => \$options{vcf},
            "output=s"           => \$options{output},
            
            "quality=f"          => \$options{min_qual},
            
            "min-supp-depth=i"   => \$options{min_supp_depth},
            "min-supp-plus=i"    => \$options{min_supp_plus},
            "min-supp-minus=i"   => \$options{min_supp_minus},
            
            "min-lib-cnt=i"      => \$options{min_lib_cnt},
            "min-lib-depth=i"    => \$options{min_lib_depth},
            "min-split-cnt=i"    => \$options{min_split_reads},
            
            "max-cmp-miss=i"     => \$options{max_cmp_missing},
            "max-cmp-depth=i"    => \$options{max_cmp_depth},
            "max-cmp-perc=f"     => \$options{max_cmp_perc},
            "max-cmp-total=i"    => \$options{max_cmp_total},
            "max-cmp-freq=s"     => \$options{max_cmp_freq},
            
            "max-shared-freq=i"  => \$options{max_shared_freq},
            "group-file=s"       => \$options{group_file},
            
            
            "no-ref-mut"         => \$options{no_ref_mut},
            
            "mask-only=s{,}"     => \@{$options{mask_only}},
            "controls=s{,}"      => \@{$options{control_samples}},
            
            "min-indel-len=i"    => \$options{min_indel_len},
            "max-indel-len=i"    => \$options{max_indel_len},
            
            "append-info"        => \$options{append_info},
           );


unless( $options{vcf} && $options{help} ) {
    print <<EOF;

$0  -- Screen out candidate mutation sites.

Version: $VERSION

Usage:   perl $0 [options]

Options:
    -v, --vcf     <filename>
        input vcf file, required
        
    *Note: This script is designed to process vcf files with AD (Allele
     Depth) field for each sample, and mainly used for processing output
     file from another script fillVcfDepth.pl, which could give all required
     informations used in this script.
     VCF file from Platypus, Delly and Manta are also supported while the
     results rely on the "NR,NV" from Platypus, "DR,DV,RR,RV" from Delly and
     "PR,SR" from Manta.
        
    -o, --output  <filename>
        output filename, default to STDOUT
    
    -a, --append-info
        Append new INFO field without replacing the original one 
    
    -f, --filter  <strings>
        skip filter loci, can have multiple values, separate by space, e.g.
        "LowQual SNPFilter ..."
    -M, --match   <strings>
        only retain loci matches, can have multiple values, separate by space,
        e.g. "PASS ..."


    -q, --quality     <float>
        loci with quality smaller than this value will filtered
    
    
    -g, --group-file  <file>
        file contain group infos of each sample, each sample per line, e.g.
        sample1 group1
        sample2 group1
        sample3 group2
        ...
        set this option to screen group-specific mutation, only samples belong
        to different groups would be used as compare samples
        
    --max-shared-freq <int>
        locus with allele frequency below this value will be considering as a
        shared mutation locus
    
    --min-supp-depth  <int>
        minimum number of supporting reads [default: 1]
    --min-supp-plus   <int>
        minimum number of supporting reads in plus strand
    --min-supp-minus  <int>
        minimum number of supporting reads in minus strand
    --min-lib-depth   <int>
        minimum number of supporting reads in each library
    --min-lib-cnt     <int>
        minimum number of supporting libraries
    --max-cmp-miss    <int>
        maximum allowed missing alleles in compare samples
    --no-ref-mut
        remove mutations with reference allele
    --min-split-cnt
        remove mutations with supporting split-read count lower than this value
        
     *Note: for sample-shared mutations, these criteria only require 1 sample
      to be passed
    
    
    --max-cmp-depth   <int>
        maximum allowed number of reads contain same mutation base (termed as
        mutation-like base here, possible from sequencing or mapping errors)
        in each compared sample, set --max-cmp-depth to 2 means none of compare
        samples could contain more than 2 mutation-like reads (e.g., FPD<=2 for
        each compared sample), a value of 3 indicates no more than 3, etc.
    --max-cmp-perc    <float>
        maximum allowed percentage of reads contain mutation-like base in
        each compared sample, this is an alternative option of "--max-cmp-depth"
    
     *Note: these two thresholds are cutoff values which actually used to
      determines whether any samples will be treated as contain "candidate
      mutation" (contain mutation-like reads more than these thresholds) or
      belong to compare samples (contain mutation-like reads no more than
      these thresholds).
      A lower value will considering more samples exceed this thresholds as
      "candidate mutation" samples, e.g. --max-cmp-depth 0 indicates samples
      contain any mutation-like reads are possible candidates, in other words
      compared samples could not have any mutation-like reads.
      A lower thresholds would give a higher false negative due to less
      tolerant of sequencing or mapping errors, while a higher thresholds
      could lead to slightly more false positives. In experience, set
      "--max-cmp-detph" to 2 will give reasonable results.
    
    
    --max-cmp-total   <int>
        maximum allowed number of total reads containing mutation-like base
        across all compared samples
        
    --max-cmp-freq    <string>
        detailed settings of maximum allowed number of reads with the mutation
        -like base in compare samples at each depth, this option should be
        setted according to "--max-cmp-depth" option, e.g.
        if "--max-cmp-depth" is set to 2, this option should have 2 values
        seperated by comma, like "3,1", which means at most 3 samples can have
        1 read, while only 1 sample can have 2 reads
    
    --controls  <strings>
        specify samples served as controls where no missing calls is allowed,
        and shared mutations contain those samples will be filtered
    
    --mask-only <strings>
        set proper FILTER field for those records failed given criteria rather
        than remove them, can have multiple values, support filtering types:
        LowDepth (--min-supp-depth)
        StrandBias (--min-supp-plus or --min-supp-minus)
        HighMissing (--max-cmp-miss)
        NonSpecific (--max-cmp-total)
        NoControl (--controls)
        LowSplitSupport (--min-split-cnt)
        Shared

EOF

    exit(1);
}

$|++;



if ($options{output}) {
    open (STDOUT, "> $options{output}") || die $!;
}


print STDERR "# $0 v$VERSION\n# " . (scalar localtime()) . "\n";



print STDERR ">> Start detecting candidate mutations in $options{vcf} ... ";
detect_mutations(\%options);
print STDERR "done!\n";


print STDERR "# " . (scalar localtime()) . "\n";

######################### Sub #########################


=head2 get_group_info

    About   : Get group infos of each sample
    Usage   : get_group_info($group_file);
    Args    : File contain group infos
    Returns : Null

=cut
sub get_group_info
{
    my ($in, $rh_group_infos) = @_;
    
    my $fh = getInputFilehandle($in);
    while (<$fh>)
    {
        next if (/\#/ || /^\s+$/);
        
        my ($sample_id, $group_id) = (split /\s+/);
        
        $rh_group_infos->{$sample_id} = $group_id;
    }
}


=head2 detect_mutations

    About   : Detect candidate mutations
    Usage   : detect_mutations($vcf_file);
    Args    : Vcf file contains all samples
    Returns : Null

=cut
sub detect_mutations
{
    my ($opts) = @_;
    

    ##
    ## parse group infos
    ##
    my %group_infos = ();
    if ($opts->{group_file}) {
        get_group_info($options{group_file}, \%group_infos);
    }
    
    ##
    ## set default values
    ##
    $opts->{min_supp_depth}  ||= 0;
    $opts->{min_supp_plus}   ||= 0;
    $opts->{min_supp_minus}  ||= 0;
    $opts->{min_lib_depth}   ||= 0;
    $opts->{min_lib_cnt}     ||= 0;
    
    
    ##
    ## check if control samples is specified
    ##
    my %control_samples = ();
    if (@{$opts->{control_samples}} > 0) {
        $control_samples{$_} = 1 for @{$opts->{control_samples}};
    }
    
    
    ##
    ## check if we have any filtered records need to be maintained in final results
    ##
    my %mask_only = ();
    if (@{$opts->{mask_only}} > 0) {
        for my $filter (@{$opts->{mask_only}})
        {
            $mask_only{$filter} = 1;
        }
    }
    
    my @sample_ids  = ();
    my %sample_rows = ();
    my $out_header  = '';
    my $fh = getInputFilehandle($opts->{vcf});
    while (<$fh>)
    {
        if (/#CHROM/) {
            my @vcf_header = (split /\s+/);
            
            next if (@sample_ids > 0);
            
            @sample_ids = @vcf_header[9..$#vcf_header];
            
            for (my $i=0; $i<@sample_ids; $i++)
            {
                $sample_rows{$sample_ids[$i]} = $i;
            }
            
            if ($mask_only{LowDepth}) {
                $out_header .= "##FILTER=<ID=LowDepth,Description=\"Low depth of mutation allele\">\n";
            }
            if ($mask_only{StrandBias}) {
                $out_header .= "##FILTER=<ID=StrandBias,Description=\"Strand bias of reads covering mutation allele\">\n";
            }
            if ($mask_only{RefNoCall}) {
                $out_header .= "##FILTER=<ID=NoControl,Description=\"No information in control samples\">\n";
            }
            if ($mask_only{HighMissing}) {
                $out_header .= "##FILTER=<ID=HighMissing,Description=\"Too many missing calls in compare samples\">\n";
            }
            if ($mask_only{NonSpecific}) {
                $out_header .= "##FILTER=<ID=NonSpecific,Description=\"Compare samples have too much reads containing mutation-like base\">\n";
            }
            if ($options{max_shared_freq} && $options{max_shared_freq} > 1) {
                $out_header .= "##FILTER=<ID=Shared,Description=\"Shared mutations among different samples except control samples\">\n";
            }
            
            $out_header .= <<EOF;
##INFO=<ID=MA,Number=1,Type=String,Description="Mutation allele">
##INFO=<ID=MAR,Number=1,Type=Float,Description="Ratio of reads contain mutation allele among all covered reads in mutation sample">
##INFO=<ID=FPD,Number=1,Type=Integer,Description="Depth of mutation-like allele in compare samples">
##INFO=<ID=FPFQ,Number=1,Type=Integer,Description="Mutation-like allele frequency of different depth in compare samples">
##INFO=<ID=FPS,Number=1,Type=String,Description="Compare samples with mutation-like alleles">
##INFO=<ID=GRPID,Number=1,Type=Integer,Description="Group ID">
##INFO=<ID=GRPD,Number=1,Type=Integer,Description="Depth of mutation-like allele in other group members">
##INFO=<ID=GRPFQ,Number=1,Type=Integer,Description="Mutation-like allele frequency of different depth in other group samples">
##INFO=<ID=GRPS,Number=1,Type=String,Description="Other group samples with mutation-like alleles">
##INFO=<ID=NMISS,Number=1,Type=Integer,Description="Number of uncallable compare samples">
##INFO=<ID=SMISS,Number=1,Type=String,Description="Uncallable compare samples">
##INFO=<ID=Shared,Number=.,Type=String,Description="Number of samples sharing this mutation allele(Details of shared samples, listed same as FORMAT field)">
##source=$SOURCE $CMDLINE
EOF
            print "$out_header";
            print "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tMUTATION\n";
            
            next;
        }
        elsif (/\#\#/ || /^\s+$/) {
            $out_header .= $_; next;
        }
        
        my ($CHROM, $POS, $ID, $REF, $ALT, $QUAL, $FILTER,
            $INFO, $FORMAT, @samples_all) = (split /\s+/);
        
        next if (defined $opts->{min_qual} && ($QUAL eq '.' || $QUAL < $opts->{min_qual}));   ## Quality filter
        
        my @vars = ($REF, (split /\,/, $ALT));
        my @tags = (split /\:/, $FORMAT);
        my %tags = ();
        for (my $i=0; $i<@tags; $i++) { $tags{$tags[$i]} = $i; }
        
        unless(defined($tags{AD}) || defined($tags{NV}) || defined($tags{DV}) || defined($tags{PR})) {
            print STDERR "Error: this script require allele read depths, while no such field was found!\n"; exit(2);
        }
        
        
        
        ##
        ## parse allele read depth
        ##
        my %read_counts     = ();
        my %allele_freq     = ();
        my %sample_infos    = ();
        my @missing_samples = ();
        for (my $i=0; $i<@samples_all; $i++)
        {
            my $AD = '.';
            
            if (defined($tags{AD})) {     ## Vcf from GATK
                $AD = (split /\:/, $samples_all[$i])[$tags{AD}];
            }
            elsif (defined($tags{NV})) {  ## Vcf from Platypus
                ## NR and NV is two tags used in Platypus
                ## FORMAT=<ID=NR,Number=.,Type=Integer,Description="Number of reads covering variant location in this sample">
                ## FORMAT=<ID=NV,Number=.,Type=Integer,Description="Number of reads containing variant in this sample">
                $AD = NRNV2AD($samples_all[$i], $tags{NR}, $tags{NV});
            }
            elsif (defined($tags{DV})) {  ## Vcf from Delly
                ## DR, DV, RR, RV is four tags used in Delly
                ## FORMAT=<ID=DR,Number=1,Type=Integer,Description="# high-quality reference pairs">
                ## FORMAT=<ID=DV,Number=1,Type=Integer,Description="# high-quality variant pairs">
                ## FORMAT=<ID=RR,Number=1,Type=Integer,Description="# high-quality reference junction reads">
                ## FORMAT=<ID=RV,Number=1,Type=Integer,Description="# high-quality variant junction reads">
                my $DR = (split /\:/, $samples_all[$i])[$tags{DR}];
                my $DV = (split /\:/, $samples_all[$i])[$tags{DV}];
                my $RR = (split /\:/, $samples_all[$i])[$tags{RR}];
                my $RV = (split /\:/, $samples_all[$i])[$tags{RV}];
                
                $AD = ($DR + $RR) . "\," . ($DV + $RV);
            }
            elsif (defined($tags{PR})) {  ## Vcf from Manta
                ## FORMAT=<ID=PR,Number=.,Type=Integer,Description="Spanning paired-read support for the ref and alt
                ## alleles in the order listed">                
                $AD = (split /\:/, $samples_all[$i])[$tags{PR}];
            }
            
            
            ##
            ## Obtain accurate read depths for each allele
            ##
            my @dps = ();
            
            if ($AD && ($AD ne '.')) {
                @dps = (split /\,/, $AD);
                
                if (@dps < @vars) { ## fix AD fields if not match
                    my $GT = (split /\:/, $samples_all[$i])[$tags{GT}];
                    
                    my $AD_fixed = fix_AD_fields($AD, $GT, scalar @vars);
                    
                    @dps = (split /\,/, $AD_fixed);
                }
            }
            else { ## if AD is missing, fill AD with 0
                @dps = (0) x (scalar @vars);
                push @missing_samples, $sample_ids[$i];
                next;
            }
            
            my $total_dp  = 0;
               $total_dp += $_ for @dps;
            
            if ($total_dp == 0) { ## An allele with no depth infos will be treated as a missing allele
                push @missing_samples, $sample_ids[$i];
                next;
            }
            
            ##
            ## Group alleles based on their depths, i.e., above or below the --max-cmp-depth threshold
            ##
            for (my $j=0; $j<@vars; $j++)
            {
                if ($dps[$j] > 0) {
                    push @{$allele_freq{$j}->{all}}, $sample_ids[$i];
                    
                    $allele_freq{$j}->{depth}->{$sample_ids[$i]} = $dps[$j];
                }
                
                ## calculate the mutation allele ratio (MA)
                my $ratio = $total_dp > 0 ? sprintf("%.2f", $dps[$j] / $total_dp) : -1;
                $allele_freq{$j}->{ratio}->{$sample_ids[$i]} = $ratio;
                
                my $perc  = 100 * $dps[$j] / $total_dp;
                
                if (defined($opts->{max_cmp_perc})) {       ## Use depth ratio rather than depth itself
                    if ($perc > $opts->{max_cmp_perc}) {
                        push @{$allele_freq{$j}->{flt}}, $sample_ids[$i];
                    }
                }
                elsif ($dps[$j] > $opts->{max_cmp_depth}) { ## Directly use the allele depth, generally better
                    push @{$allele_freq{$j}->{flt}}, $sample_ids[$i];
                }
            }
            
            $sample_infos{$sample_ids[$i]}  = $samples_all[$i]; ## Save sample details for output
        }
        
        
        
        ##
        ## screen out candidate mutational alleles
        ##
        for my $allele (sort keys %allele_freq)     ## check all alleles at each locus
        {
            next if (defined($opts->{no_ref_mut}) && $allele == 0); ## skip reference allele
            
            next unless($allele_freq{$allele}->{flt}); ## skip if no allele satisfies the depth threshold
            
            ## check allele frequency
            my @mut_samples  = sort @{$allele_freq{$allele}->{flt}};  ## focal samples: samples supposed to carry a mutational allele
            my @sample_infos = ();
            
            for my $sample (@mut_samples)
            {
                push @sample_infos, $sample_infos{$sample};
            }
            
            ##
            ## Group filter
            ##  Assume each mutation should only present within a single specified group,
            ##  remove mutations shared between groups
            ##
            my %mut_groups   = ();
            if ($opts->{group_file}) {
                $mut_groups{$group_infos{$_}}++ for @mut_samples;
                next if (scalar (keys %mut_groups) > 1);
            }
            
            my $mut_freq = scalar @mut_samples;
            
            ##
            ## Using other metrics to filter candidate mutations
            ##
            my %filtered = ();
            for (my $i=0; $i<@mut_samples; $i++)
            {
                ##
                ## Obtain allele read depth
                ##
                my $AD = '.';
                
                if (defined($tags{AD})) {     ## Vcf from GATK
                    $AD = (split /\:/, $sample_infos[$i])[$tags{AD}];
                }
                elsif (defined($tags{NV})) {  ## Vcf from Platypus
                    ## NR and NV is two tags used in Platypus
                    ## FORMAT=<ID=NR,Number=.,Type=Integer,Description="Number of reads covering variant location in this sample">
                    ## FORMAT=<ID=NV,Number=.,Type=Integer,Description="Number of reads containing variant in this sample">
                    $AD = NRNV2AD($sample_infos[$i], $tags{NR}, $tags{NV});
                }
                elsif (defined($tags{DV})) {  ## Vcf from Delly
                    ## DR, DV, RR, RV is four tags used in Delly
                    ## FORMAT=<ID=DR,Number=1,Type=Integer,Description="# high-quality reference pairs">
                    ## FORMAT=<ID=DV,Number=1,Type=Integer,Description="# high-quality variant pairs">
                    ## FORMAT=<ID=RR,Number=1,Type=Integer,Description="# high-quality reference junction reads">
                    ## FORMAT=<ID=RV,Number=1,Type=Integer,Description="# high-quality variant junction reads">
                    my $DR = (split /\:/, $sample_infos[$i])[$tags{DR}];
                    my $DV = (split /\:/, $sample_infos[$i])[$tags{DV}];
                    my $RR = (split /\:/, $sample_infos[$i])[$tags{RR}];
                    my $RV = (split /\:/, $sample_infos[$i])[$tags{RV}];
                    
                    $AD = ($DR + $RR) . "\," . ($DV + $RV);
                }
                elsif (defined($tags{PR})) {  ## Vcf from Manta
                    ## FORMAT=<ID=PR,Number=.,Type=Integer,Description="Spanning paired-read support for the ref and alt
                    ## alleles in the order listed">
                    $AD = (split /\:/, $samples_all[$i])[$tags{PR}];
                }
                
                my @dps = (split /\,/, $AD);
                
                if (@dps < @vars) {
                    ## fix AD fields if not match
                    my $GT = (split /\:/, $sample_infos[$i])[$tags{GT}];
                    
                    my $AD_fixed = fix_AD_fields($AD, $GT, scalar @vars);
                    
                    @dps = (split /\,/, $AD_fixed);
                }
                
                
                ##
                ## Read Depth filter
                ##
                if ($dps[$allele] < $opts->{min_supp_depth}) {
                    push @{$filtered{LowDepth}}, $mut_samples[$i]; 
                }
                
                ##
                ## Strand-bias filter
                ##  Allele with biased strands (only foward or only reverse strand) are prone to be mapping errors
                ##
                if ($tags{RC}) {
                    my $RC  = (split /\:/, $sample_infos[$i])[$tags{RC}];
                    my @detail_dps = split /\,/, $RC;
                    
                    if (@detail_dps > 1) {
                        if ($detail_dps[2*$allele] < $opts->{min_supp_plus} || $detail_dps[2*$allele+1] < $opts->{min_supp_minus}) {
                            push @{$filtered{StrandBias}}, $mut_samples[$i]; 
                        }
                    }
                }
                
                ##
                ## Replicate filter
                ##  If a sample was sequenced by multiple strategy/libraries/etc., require consistency across
                ##  each replicate
                ##
                if (($opts->{lib_cnt} || $opts->{min_lib_depth}) && $tags{LN} && $tags{LAD}) {
                    my $LN  = (split /\:/, $sample_infos[$i])[$tags{LN}];
                    
                    if ($LN < $opts->{min_lib_cnt}) {
                        push @{$filtered{LibraryBias}}, $mut_samples[$i]; next;
                    }
                    
                    my $LAD = (split /\:/, $sample_infos[$i])[$tags{LAD}];
                    
                    my @lib_dps = split /\,/, $LAD;
                    my $lib_cnt = 0;
                    
                    for (my $i=0; $i<$LN; $i++)
                    {
                        my $dp = $lib_dps[$allele*$LN+$i];
                        
                        $lib_cnt++ if ($dp >= $opts->{min_lib_depth});
                    }
                    
                    if ($lib_cnt < $opts->{lib_cnt}) {
                        push @{$filtered{LibraryBias}}, $mut_samples[$i];
                    }
                }
                
                
                ##
                ## Split-read filter
                ##  Check whether the mutation could be supported by split-read count;
                ##  purposed for SV mutations from caller like Manta
                ##
                if ($opts->{min_split_reads}) {
                    if (defined($tags{SR})) { ## For Manta Vcf
                        ## FORMAT=<ID=SR,Number=.,Type=Integer,Description="Split reads for the ref and alt alleles in the
                        ## order listed, for reads where P(allele|read)>0.999">
                        my $SR = (split /\:/, $samples_all[$i])[$tags{SR}];
                        
                        my @split_reads = (split /\,/, $SR);
                        
                        if ($split_reads[$allele] < $opts->{min_split_reads}) {
                            push @{$filtered{LowSplitSupport}}, $mut_samples[$i]; 
                        }
                    }
                    else {
                        push @{$filtered{LowSplitSupport}}, $mut_samples[$i];
                    }
                }
            }
            
            
            ##
            ## process FILTER field
            ##
            my %out_filters = ();
            if (($FILTER ne '.') && ($FILTER ne 'PASS')) {
                my @filters = split /;/, $FILTER;
                $out_filters{$_} = 1 for @filters;
            }
            
            ##
            ## Control-based filter
            ##  Check whether the control samples were missing
            ##
            my @missing_controls = grep { $control_samples{$_} } @missing_samples;
            if (@missing_controls > 0) {
                if ($mask_only{NoControl}) {
                    $out_filters{NoControl} ++;
                }
                else {
                    next;
                }
            }
            
            ##
            ## Frequency filter:
            ##  Remove mutations shared by more than $options{max_shared_freq} samples;
            ##  remove mutations shared with control samples
            ##
            if ($options{max_shared_freq} && $mut_freq > 1) {
                if ($mut_freq > $options{max_shared_freq}) {
                    next;
                }
                else {
                    my @shared_controls = grep { $control_samples{$_} } @mut_samples; ## could not shared with control samples
                    
                    next if (@shared_controls > 0);
                    
                    if ($mask_only{Shared}) {
                        $out_filters{Shared} ++;
                    }
                }
            }
            
            ##
            ## Determine how to apply all filters
            ##  Soft-filtering: mask those loci with all mutation samples failed any defined criteria
            ##  Hard-filtering: remove those loci with all mutation samples failed any defined criteria
            ##
            my $filter_tag = 0;
            for my $filter (sort keys %filtered)
            {
                if ((scalar @{$filtered{$filter}}) >= $mut_freq) {
                    if ($mask_only{$filter}) {
                        $out_filters{$filter} ++;
                    }
                    else {
                        $filter_tag = 1; last;
                    }
                }
            }
            
            next if ($filter_tag);
            
            
            ##
            ## Update INFO field in output Vcf file
            ##
            my $INFO_new = "FPD=0;FPFQ=0;FPS=NA;MA=$vars[$allele]";
            

            ##
            ## Allele-depth filter
            ##  Frequent occurrence of non-focal samples(samples not passed the --max-cmp-depth) from other groups 
            ##  carry reads of mutation-like allele is a strong indication of systematic artefacts
            ##
            my %mut_samples = ();
               $mut_samples{$_} = 1 for @mut_samples;
               
            my @samples_flt = grep { !$mut_samples{$_} } @{$allele_freq{$allele}->{all}};
            
            if ($opts->{group_file}) { ## only considering samples from other groups as compare samples
                @samples_flt = grep { !$mut_groups{$group_infos{$_}} } @samples_flt;
            }
            
            if (@samples_flt > 0) {
                my %fp_dps = ();
                
                my $fp_depth_total = 0;
                for my $sample (@samples_flt)
                {
                    my $dp = $allele_freq{$allele}->{depth}->{$sample};
                    
                    push @{$fp_dps{$dp}}, $sample;
                    
                    $fp_depth_total += $dp;
                }
                
                if (defined($options{max_cmp_total}) && $fp_depth_total > $options{max_cmp_total}) {
                    if ($mask_only{NonSpecific}) {
                        $out_filters{NonSpecific} ++;
                    }
                    else {
                        next;
                    }
                }
                
                my @fp_depths  = sort {$a <=> $b} keys %fp_dps;
                my @fp_freqs   = ();
                my @fp_samples = ();
                for my $dp (@fp_depths)
                {
                    my $fq = scalar @{$fp_dps{$dp}};
                    
                    push @fp_freqs, $fq;
                    
                    my $samples = join ',', (sort @{$fp_dps{$dp}});
                    
                    push @fp_samples, "($samples)";
                }
                
                my $fp_depths  = join ',', @fp_depths;
                my $fp_freqs   = join ',', @fp_freqs;
                my $fp_samples = join ',', @fp_samples;
                
                $INFO_new = "FPD=$fp_depths;FPFQ=$fp_freqs;FPS=$fp_samples;MA=$vars[$allele]";
            }
            
            if ((scalar @mut_samples) == 1) {
                $INFO_new .= ";MAR=$allele_freq{$allele}->{ratio}->{$mut_samples[0]}";
            }
            
            ##
            ## Missing filter
            ##  Check whether there are too many missing calls which made the above comparison unreliable
            ##
            my $missing_cnt     = scalar @missing_samples;
            my $missing_samples = join ',', @missing_samples;
            
            if (defined $opts->{max_cmp_missing} && $missing_cnt > $opts->{max_cmp_missing}) {
                if ($mask_only{HighMissing}) {
                    $out_filters{HighMissing} ++;
                }
                else {
                    next;
                }
            }
            
            
            ##
            ## Formating output
            ##
            if ($missing_cnt > 0) {
                $INFO_new = "NMISS=$missing_cnt;SMISS=$missing_samples;" . $INFO_new;
            }
            else {
                $INFO_new = "NMISS=0;SMISS=NA;" . $INFO_new;
            }
            
            if ($mut_freq > 1) {
                my $sample_details = join "|", @sample_infos;
                $INFO_new .= ";Shared=$mut_freq($sample_details)";
            }

            ##
            ## Try to give more details about non-focal samples within the same group of focal samples
            ##
            if ($opts->{group_file}) {
                my $mut_group = $group_infos{$mut_samples[0]};
                my @group_flt = grep { !$mut_samples{$_} && $mut_groups{$group_infos{$_}} } @{$allele_freq{$allele}->{all}};
                
                if (@group_flt > 0) {
                    my %group_dps = ();
                    
                    my $group_depth_total = 0;
                    for my $sample (@group_flt)
                    {
                        my $dp = $allele_freq{$allele}->{depth}->{$sample};
                        
                        push @{$group_dps{$dp}}, $sample;
                        
                        $group_depth_total += $dp;
                    }
                    
                    my @group_depths  = sort {$a <=> $b} keys %group_dps;
                    my @group_freqs   = ();
                    my @group_samples = ();
                    for my $dp (@group_depths)
                    {
                        my $fq = scalar @{$group_dps{$dp}};
                        
                        push @group_freqs, $fq;
                        
                        my $samples = join ',', (sort @{$group_dps{$dp}});
                        
                        push @group_samples, "($samples)";
                    }
                    
                    my $group_depths  = join ',', @group_depths;
                    my $group_freqs   = join ',', @group_freqs;
                    my $group_samples = join ',', @group_samples;
                    
                    $INFO_new .= ";GRPID=$mut_group;GRPD=$group_depths;GRPFQ=$group_freqs;GRPS=$group_samples";
                }
                else {
                    $INFO_new .= ";GRPID=$mut_group";
                }
            }
            
            my @out_filters = (sort keys %out_filters);
            
            my $FILTER_new = $FILTER;
            if (@out_filters > 0) {
                $FILTER_new = join ";", @out_filters;
            }
            
            
            if ($opts->{append_info}) {
                $INFO_new = $INFO . ";" . $INFO_new;
            }
            
            
            my $mut_samples  = join ";", @mut_samples;
            print "$CHROM\t$POS\t$mut_samples\t$REF\t$ALT\t$QUAL\t$FILTER_new\t$INFO_new\t$FORMAT\t$sample_infos[0]\n";
        }
    }
}

