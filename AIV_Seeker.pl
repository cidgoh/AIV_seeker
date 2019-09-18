#!/usr/bin/perl -w
# Detect avian influenza virus in NGS metagenomics DATA 
#
# Jun Duan
# BCCDC Public Health Laboratory
# University of British Columbia
# jun.duan@bccdc.ca
#
# William Hsiao, PhD
# Senior Scientist (Bioinformatics), BCCDC Public Health Laboratory
# Clinical Assistant Professor, Pathology & Laboratory Medicine, UBC
# Adjunct Professor, Molecular Biology and Biochemistry, SFU
# Rm 2067a, 655 West 12th Avenue 
# Vancouver, BC, V5Z 4R4
# Canada
# Tel: 604-707-2561
# Fax: 604-707-2603

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use Config::IniFiles;

my ($help, $NGS_dir, $result_dir,$flow);
my ($step,$threads,$BSR,$margin,$percent,$overlap_level,$level,$identity_threshold,$cluster_identity,$chimeric_threshold);

GetOptions(
    'help|?' => \$help,
    'dir|i=s' => \$NGS_dir,
    'outputfile|o=s' => \$result_dir,
    'threads|t=s' => \$threads,
    'step|s=i' => \$step,
    'BSR|b=f' => \$BSR,
    'margin|m=f' => \$margin,
    'percent|p=f' => \$percent,
    'flow|f' => \$flow,
    'level|l=f' => \$overlap_level,
    'identity_threshold|x=f' => \$identity_threshold,
    'chimeric_threshold|z=f' => \$chimeric_threshold,
    'cluster_identity|c=f' => \$cluster_identity,
  );

if($help || !defined $NGS_dir || !defined $result_dir ) {

die <<EOF;

################################################

AIV_Seeker: Pipeline for detecting avian influenza virus from NGS Data

BC Centre for Disease Control
University of British Columbia

################################################

Usage: perl AIV_seeker.pl -i run_folder -o result_folder    
         -i	path for NGS fastq file directory
         -o	result folder
         -s	step number
         		step 1: Generate the fastq file list
         		step 2: Generate QC report
         		step 3: Quality filtering and merging
         		step 4: First search by Diamond
         		step 5: Cluster reads
         		step 6: Second search by BLAST
         		step 7: Remove chimeric sequences
         		step 8: cross-contamination detection
         		step 9: Detect subtype
         		step 10: Generate report
         -f	run the current step and following steps (default false), no parameter
         -b	BSR score (default 0.4)
         -m	margin of BSR score (default 0.3)
         -p	percentage of concordant subtype (default 0.9)
         -t	number of threads
         -h	display help message
         -l overlap level (default 0.7)
         -x threshold for identity (default 90%)
         -z threshold for chimeric check (default 90%)
         -c identity for clustering when dealing with cross-talking (default 0.97)
         
EOF
}

my $exe_path = dirname(__FILE__);
my $config_file = "$exe_path/config/config.ini";
our $ini = Config::IniFiles->new(
        -file    => $config_file
        ) or die "Could not open $config_file!";

my $path_db = $ini->val( 'database', 'path_db' );
$step = $step || 0;
$threads = $threads || 45;
$BSR = $BSR || 0.4;
$margin = $margin || 0.3;
$percent = $percent || 0.9;
$level = $overlap_level || 0.7;
$identity_threshold = $identity_threshold || 90;
$chimeric_threshold = $chimeric_threshold || 0.75;
$cluster_identity=$cluster_identity||0.97;

if (-d "$NGS_dir") {
	$NGS_dir=~s/\/$//;
}
else {
    print "The input fastq file directory is not existing, please check!\n";
    exit;
}

check_folder($result_dir);
my $run_list="$result_dir/filelist.txt";

if($step==1 or $step==0) {
	&check_filelist($run_list);
	if($flow) { 
		$step=2;
	}			
}
my @files=&get_lib_list($run_list);

if($step>1) {
	if($step==2) {
		&QC_report($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
	if($step==3) {
		&quality_filtering($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
    if($step==4) {
        check_folder("$result_dir/tmp");
		&search_by_diamond($result_dir,\@files);	
		if($flow) { 
			$step=$step+1;
		}
    }
    if($step==5) {
		&get_AIV_reads($result_dir,\@files);
		&cluster_AIV_reads_vsearch($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
    if($step==6) {
		&blast_AIV($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
	if($step==7) {
		&remove_chimeric($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
	if($step==8) {
		&debleeding($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
   	if($step==9) {
		&assign_subtype_debled($result_dir,\@files);
		if($flow) { 
			$step=$step+1;
		}
    }
    if($step==10) {
		&debled_report($result_dir,\@files);
    }
}

    
sub check_filelist() {
	my ($run_list) = @_;
	if (-e $run_list) {
		print "File list is already existing. Would you like to generate a new list (Y/N):";
		my $checkpoint;
		do {
			my $input = <STDIN>;
			chomp $input;
      		if($input =~ m/^[Y]$/i) {
      			system("perl $exe_path/module/scan_NGS_dir.pl -i $NGS_dir -o $run_list");
      			$checkpoint=1;
      		} 
      		elsif ($input =~ m/^[N]$/i) {
          		print "You said no, so we will use the existing $run_list\n";
          		$checkpoint=2;
      		} 
      		else {
         		print "Invalid option, please input again (Y/N):";
      		}
      	} while ($checkpoint<1) ;
    }
    else {
    	system("perl $exe_path/module/scan_NGS_dir.pl -i $NGS_dir -o $run_list");
    }
}

sub get_lib_list() {
	my ($run_list) = @_;
	my @libs;
	open(IN,$run_list);
	while(<IN>) {
		chomp;
		my $line=$_;
		if($line) {
			push @libs,$line;
		}
	}
	close IN;
	return @libs;
}

sub QC_report () {
	my ($result_dir,$files) = @_;
	my $dir_raw="$result_dir/0.raw_fastq";
    my $dir_QC="$result_dir/1.QC_report";
	check_folder($dir_raw);
	check_folder($dir_QC);
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
  		system("gunzip -c $libs[1] >$dir_raw/$libname\_R1.fq");
	    system("gunzip -c $libs[2] >$dir_raw/$libname\_R2.fq");
		system("fastqc -t $threads $dir_raw/$libname\_R1.fq -o $dir_QC");
		system("fastqc -t $threads $dir_raw/$libname\_R2.fq -o $dir_QC");
 	}
}


sub quality_filtering () {
	my ($result_dir,$files) = @_;
	my $dir_raw="$result_dir/0.raw_fastq";
    my $dir_file_processed="$result_dir/2.file_processed";
    my $dir_fasta_processed="$result_dir/3.fasta_processed";
	check_folder($dir_file_processed);
	check_folder($dir_fasta_processed);
	my $trimmomatic = $ini->val( 'tools', 'trimmomatic');
    my $flash = $ini->val( 'tools', 'flash');
    my $fastq_to_fasta = $ini->val( 'tools', 'fastq_to_fasta');
    my $adaptor = $ini->val( 'database', 'adaptor');
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
        system("perl $exe_path/module/convert_fastq_name.pl $dir_raw/$libname\_R1.fq $dir_raw/$libname\_N\_R1.fq");
        #system("rm -fr $dir_raw/$libname\_R1.fq");
		system("perl $exe_path/module/convert_fastq_name.pl $dir_raw/$libname\_R2.fq $dir_raw/$libname\_N\_R2.fq");
		#system("rm -fr $dir_raw/$libname\_R2.fq");
        system("java -jar $trimmomatic PE -threads $threads -phred33 $dir_raw/$libname\_N\_R1.fq $dir_raw/$libname\_N\_R2.fq $dir_file_processed/$libname\_P\_R1.fq $dir_file_processed/$libname\_S\_R1.fq $dir_file_processed/$libname\_P\_R2.fq  $dir_file_processed/$libname\_S\_R2.fq  ILLUMINACLIP\:$adaptor\:2:30:10 LEADING:20 TRAILING:20 SLIDINGWINDOW:4:20  MINLEN:60");
        system("cat $dir_file_processed/$libname\_P\_R1.fq $dir_file_processed/$libname\_P\_R2.fq $dir_file_processed/$libname\_S\_R1.fq $dir_file_processed/$libname\_S\_R2.fq >$dir_file_processed/$libname\_combine.fastq");
        system("$fastq_to_fasta -Q 33 -i $dir_file_processed/$libname\_combine.fastq -o $dir_fasta_processed/$libname\_raw.fasta");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_raw/$libname\_N\_R1.fq >>$result_dir/fastq_sequence_sum.txt");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_raw/$libname\_N\_R2.fq >>$result_dir/fastq_sequence_sum.txt");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_file_processed/$libname\_P\_R1.fq >>$result_dir/fastq_sequence_sum.txt");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_file_processed/$libname\_P\_R2.fq >>$result_dir/fastq_sequence_sum.txt");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_file_processed/$libname\_S\_R1.fq >>$result_dir/fastq_sequence_sum.txt");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_file_processed/$libname\_S\_R2.fq >>$result_dir/fastq_sequence_sum.txt");
        system("perl $exe_path/module/sum_fastq_file.pl -i $dir_file_processed/$libname\_combine.fastq >>$result_dir/fastq_sequence_sum.txt"); 
    }
    system("perl $exe_path/module/sum_table.pl -i $result_dir/fastq_sequence_sum.txt -o $result_dir/sum.txt");
}

sub search_by_diamond () {
	my ($result_dir,$files) = @_;
	my $dir_fasta_processed="$result_dir/3.fasta_processed";
	my $dir_diamond="$result_dir/4.diamond";
	my $diamond_db = $ini->val( 'database', 'diamond_db');
    my $diamond = $ini->val( 'tools', 'diamond');
	check_folder($dir_diamond);	
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
        system("$diamond blastx -d $diamond_db -q $dir_fasta_processed/$libname\_raw\.fasta -a $libname -e 0.00001 -p $threads -t $result_dir/tmp --salltitles");
        system("$diamond view -a $libname\.daa -o $dir_diamond/$libname\.m8");
        system("rm -fr $libname\.daa");
    }
}


sub get_AIV_reads () {
	my ($result_dir,$files) = @_;
    my $dir_file_processed="$result_dir/3.fasta_processed";
    my $dir_diamond="$result_dir/4.diamond";
    my $aiv_reads_first_round="$result_dir/5.clustered_reads";    
	check_folder($aiv_reads_first_round);
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
		system("perl $exe_path/module/get_reads_first_round.pl -i $dir_diamond/$libname\.m8 -d $dir_file_processed/$libname\_raw\.fasta -o $aiv_reads_first_round/$libname\_first_round.fa");
	}
}

sub cluster_AIV_reads_vsearch () {
	my ($result_dir,$files) = @_;
	my $aiv_reads="$result_dir/5.clustered_reads";
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
        my $source=$libs[3];
        my $p1="vsearch --threads $threads --derep_fulllength $aiv_reads/$libname\_first_round.fa --output $aiv_reads/$libname\_reads_derep.fa --sizeout --uc $aiv_reads/$libname\_vsearch-derep.uc";
        my $p2="perl $exe_path/module/add_tag_to_seq.pl $aiv_reads/$libname\_reads_derep.fa $aiv_reads/$libname\_reads_derep_with_tag.fa $libname";
        if(-s "$aiv_reads/$libname\_first_round.fa") {   
            system($p1);
            system($p2);
        }
    }
}


sub blast_AIV () {
	my ($result_dir,$files) = @_;
	my $blast_dir="$result_dir/6.blast";
	my $blast_dir_vs_db="$blast_dir/1.blast_to_db";
	my $blast_dir_self="$blast_dir/2.blast_to_self";
	my $aiv_reads="$result_dir/5.clustered_reads";
	my $GISAID = $ini->val( 'database', 'GISAID');
	check_folder($blast_dir);
    check_folder($blast_dir_vs_db);
    check_folder($blast_dir_self);
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
        my $source=$libs[3];
        my $p1="blastall -i $aiv_reads/$libname\_reads_derep_with_tag.fa -d $GISAID -o $blast_dir_vs_db/$libname\_blastout.m8 -p blastn -e 1e-20 -F F -b 250 -v 250 -m 8 -a $threads";
       	my $p2="formatdb -i $aiv_reads/$libname\_reads_derep_with_tag.fa -p F";
		my $p3="blastall -p blastn -i $aiv_reads/$libname\_reads_derep_with_tag.fa -d $aiv_reads/$libname\_reads_derep_with_tag.fa -o $blast_dir_self/$libname\_self.m8 -m 8 -e 1e-10 -F F -b 1 -v 1 -a $threads";
        if(-s "$aiv_reads/$libname\_reads_derep_with_tag.fa") {   
        	system($p1);
        	system($p2);
           	system($p3);
        }
    }
}

sub remove_chimeric() {
	my ($result_dir,$files) = @_;
	my $dir_chimeric="$result_dir/7.check_chimeric";
    my $dir_chimeric_processed="$dir_chimeric/1.processed";
	my $dir_chimeric_seq="$dir_chimeric/2.de_chimeric_seq";
	my $blast_dir="$result_dir/6.blast";
	my $blast_dir_vs_db="$blast_dir/1.blast_to_db";
	my $blast_dir_self="$blast_dir/2.blast_to_self";
	my $aiv_reads="$result_dir/5.clustered_reads";
	check_folder($dir_chimeric);
	check_folder($dir_chimeric_processed);
	check_folder($dir_chimeric_seq);      
    foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
        my $source=$libs[3];            
        system("perl $exe_path/module/remove_chimeric.pl -c $chimeric_threshold -i $blast_dir_vs_db/$libname\_blastout.m8 -d $aiv_reads/$libname\_reads_derep_with_tag.fa -o $dir_chimeric_processed/$libname\_chimeric\_$chimeric_threshold\.txt >$dir_chimeric_processed/$libname\_without_chimeric\_$chimeric_threshold\.txt");
        if(-s "$dir_chimeric_processed/$libname\_without_chimeric\_$chimeric_threshold\.txt") {
			system("perl $exe_path/module/get_reads_first_round.pl -i $dir_chimeric_processed/$libname\_without_chimeric\_$chimeric_threshold\.txt -d $aiv_reads/$libname\_reads_derep_with_tag.fa -o $dir_chimeric_seq/$libname\_no_chimeric.fa");
        }
    }
}

sub debleeding() {
	my ($result_dir,$files) = @_;
	my $vsearch = $ini->val( 'tools', 'vsearch');
    my %source_all;
    my $dir_chimeric_seq="$result_dir/7.check_chimeric/2.de_chimeric_seq";
    my $dir_debled="$result_dir/8.debled\_$cluster_identity";
    my $dir_combined_seq="$dir_debled/0.combined_seq";
    check_folder($dir_combined_seq);
    system("rm -fr $dir_combined_seq/*");
	foreach my $items(@$files) {
		my @libs= split(/\t/,$items); 
		my $libname=$libs[0];
		my $source=$libs[3]; 
		if($source) {
			$source_all{$source}=1;
		}
		if(-s "$dir_chimeric_seq/$libname\_no_chimeric.fa") {
			system("cat $dir_chimeric_seq/$libname\_no_chimeric.fa >>$dir_combined_seq/$source\_debled_step1.fa");
		}
    }
	my $dir_debled_step1_vsearch_out="$dir_debled/1.step_vsearch_out";
	my $dir_debled_step2_otu="$dir_debled/2.step_otu";
	my $dir_debled_step3_otu_processed="$dir_debled/3.step_otu_processed";
	my $dir_debled_step4_cross="$dir_debled/4.step_cross_detection";
	my $dir_debled_step5_cross_removed="$dir_debled/5.step_cross_removed";
	my $dir_debled_step6_reads_list="$dir_debled/6.step_reads_list";
    my $debled_reads_ok="$dir_debled/7.debled_reads_ok";
    check_folder($dir_debled_step1_vsearch_out);
    check_folder($dir_debled_step2_otu);
	check_folder($dir_debled_step3_otu_processed);
	check_folder($dir_debled_step4_cross);
	check_folder($dir_debled_step5_cross_removed);
	check_folder($dir_debled_step6_reads_list);
	check_folder($debled_reads_ok);
	foreach my $source(keys %source_all) {
		system("$vsearch --threads $threads --cluster_size $dir_combined_seq/$source\_debled_step1.fa --id $cluster_identity --target_cov 0.6 --centroids $dir_debled_step1_vsearch_out/$source\_centroids.fa --uc $dir_debled_step1_vsearch_out/$source\_reads_cluster.uc --strand both --sizeout");
		system("perl $exe_path/module/parse_uc_to_otu.pl -i $dir_debled_step1_vsearch_out/$source\_reads_cluster.uc -m $dir_debled_step2_otu/$source\_otu.txt -n $dir_debled_step2_otu/$source\_otu_name.txt -x $dir_debled_step2_otu/$source\_otu_orginal.txt");
		system("perl $exe_path/module/parse_otu.pl -i $dir_debled_step2_otu/$source\_otu_orginal.txt -m $dir_debled_step3_otu_processed/$source\_otu_uniq.txt -n $dir_debled_step3_otu_processed/$source\_otu_cross.txt");
		system("perl $exe_path/module/detect_cross_talk.pl -i $dir_debled_step3_otu_processed/$source\_otu_cross.txt -o $dir_debled_step4_cross/$source\_otu_cross_removed.txt -m $dir_debled_step4_cross/$source\_otu_cross_multiple_dominant.txt -n $dir_debled_step4_cross/$source\_otu_cross_single_dominant.txt");
		system("cat $dir_debled_step3_otu_processed/$source\_otu_uniq.txt $dir_debled_step4_cross/$source\_otu_cross_removed.txt >$dir_debled_step5_cross_removed/$source\_otu_processed.txt");
		system("perl $exe_path/module/get_debleeded_reads_list_x.pl -i $dir_debled_step5_cross_removed/$source\_otu_processed.txt -d $dir_debled_step2_otu/$source\_otu_name.txt -o $dir_debled_step6_reads_list/$source\_reads_list_ok.txt");
		system("perl $exe_path/module/get_reads_first_round.pl -i $dir_debled_step6_reads_list/$source\_reads_list_ok.txt -d $dir_combined_seq/$source\_debled_step1.fa -o $dir_debled_step6_reads_list/$source\_reads_all_ok.fa");
		system("perl $exe_path/module/divide_fasta_into_lib.pl $dir_debled_step6_reads_list/$source\_reads_all_ok.fa $debled_reads_ok $source");
	}
 }

 sub assign_subtype_debled () {
	my ($result_dir,$files) = @_;
	my $blast_dir_vs_db="$result_dir/6.blast/1.blast_to_db";
	my $blast_dir_self="$result_dir/6.blast/2.blast_to_self";
	my $cluster_subtype="$result_dir/9.subtype\_$cluster_identity";
	my $cluster_subtype_step1_blast_sorted="$cluster_subtype/1.step_blast_sorted";
	my $cluster_subtype_step2_subtype="$cluster_subtype/2.step_subtype_file";
	my $cluster_subtype_step3_seq="$cluster_subtype/3.step_subtype_seq";
	check_folder($cluster_subtype_step1_blast_sorted);
	check_folder($cluster_subtype_step2_subtype);
  	check_folder($cluster_subtype_step3_seq);
  	my $debled_reads_ok="$result_dir/8.debled\_$cluster_identity/7.debled_reads_ok";
	foreach my $items(@$files) {
        my @libs= split(/\t/,$items); 
        my $libname=$libs[0];
        my $source=$libs[3];
		check_folder("$cluster_subtype_step3_seq/$source");
        my $GISAID_relation = $ini->val( 'database', 'GISAID_relation');
		if(-s "$debled_reads_ok/$source/$libname\_reads_ok.fa") {
			system("perl $exe_path/module/parse_m8_BSR.pl -i $blast_dir_vs_db/$libname\_blastout.m8 -s $blast_dir_self/$libname\_self.m8 -d $GISAID_relation -o $cluster_subtype_step1_blast_sorted/$libname\_sorted.txt -m $debled_reads_ok/$source/$libname\_reads_ok.fa");
			if(-s "$cluster_subtype_step1_blast_sorted/$libname\_sorted.txt") {
				system("perl $exe_path/module/assign_subtype_v2.pl -i $cluster_subtype_step1_blast_sorted/$libname\_sorted.txt -o $cluster_subtype_step2_subtype/$libname\_subtype.txt -u $cluster_subtype_step2_subtype/$libname\_unclassified.txt -m $margin -b $BSR -p $percent");
				system("perl $exe_path/module/sum_subtype_depricated.pl -i $cluster_subtype_step2_subtype/$libname\_subtype.txt -o $cluster_subtype_step2_subtype/$libname\_summary_depricated.txt");
				system("perl $exe_path/module/getseq_subtype.pl -i $cluster_subtype_step2_subtype/$libname\_subtype.txt -d $debled_reads_ok/$source/$libname\_reads_ok.fa -o $cluster_subtype_step3_seq/$source");
			}
		}
	}
}

sub debled_report() {
	my $dir_report="$result_dir/10.report\_$cluster_identity";
	check_folder($dir_report);
	system("cat $result_dir/9.subtype\_$cluster_identity/2.step_subtype_file/*_summary_depricated.txt >$dir_report/subtype_report_debled_unsorted_depricated.txt");
	my $gc_sum="$result_dir/sum.txt";
	my $input="$dir_report/subtype_report_debled_unsorted_depricated.txt";
    my $output="$dir_report/report_debled";
	&generate_report_cluster($gc_sum,$input,$output);
	system("rm -fr $input");
}


sub check_folder {
	my ($folder) = @_;
	if (-d $folder) { }
	else {
   		system("mkdir -p $folder");
   	}		 
}

sub generate_report_cluster () {
	my ($gc_sum,$input,$output) = @_;
  	system("perl $exe_path/module/generate_report_cluster.pl -i $input -m $gc_sum -o $output");
}