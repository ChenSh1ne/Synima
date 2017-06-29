package Ort;
use strict 'vars';
use strict 'refs';
use Data::Dumper;
use File::Basename;

sub new {
	my ($filename, $gene_identifying_feature, $format, $genome_codes) = @_;
	die "Error: Ort.pm. GIF should be be gene or transcript" if(($gene_identifying_feature ne 'gene') && ($gene_identifying_feature ne 'transcript'));
	die "Error: Ort.pm. Format should be RBH, RBH_Calhoun or OMCL" if(($format ne  'RBH') && ($format ne 'RBH_Calhoun') && ($format ne 'OMCL'));
	die "Error: Ort.pm. Genome codes required" if(!defined $genome_codes);

	my $self = {
		filename                 => $filename,
		gene_identifying_feature => $gene_identifying_feature,
		format                   => $format,
		genome_codes             => $genome_codes
	};

	bless $self, Ort;
	return $self;
}

sub get_filename {
	my $self = shift;
	return $self->{filename};
}

sub read {
	my $self = shift;
	$self->read_RBH() if (($self->{format} eq "RBH") || ($self->{format} eq "RBH_Calhoun"));
	$self->read_OMCL() if($self->{format} eq "OMCL");
	@{ $self->{cluster_ids} } = sort { $a <=> $b } keys( %{ $self->{cluster_ids_hash} } );
}

sub read_OMCL {
	my $self = shift;

	#my ($name, $base_dir, $ext) = fileparse( $self->{filename} );
	#my $genome_idx_file = "$base_dir/for_omcl.genome_codes";

	# Genome index file: for_omcl.genome_codes
	#EFCM_Com12_V1_FINAL_CALLGENES_2 G001
	#ECAS_EC20_V1_FINAL_CALLGENES_1 G002
	#EFCM_Com15_V1_FINAL_CALLGENES_1 G003

	#open GENOME_IDX_FILE, $genome_idx_file or die "Unable to open OrthoMCL genome index file " . $genome_idx_file . "\n";
	open my $fh, '<', $self->{genome_codes} or die "Unable to open OrthoMCL genome index file " . $self->{genome_codes} . "\n";
	warn "Saving genome codes $self->{genome_codes}...\n";
	while (my $line=<$fh>) {
		chomp $line;
		my ($org_name, $org_num_hex) = split " ", $line;
		$org_num_hex =~ s/^G*//;
		my $org_num = hex( $org_num_hex);
		$self->{org_num}{$org_name} = $org_num;
		$self->{org_name}[$org_num] = $org_name;
	}
	close $fh;

	# Cluster file: all_orthomcl.out
	#ORTHOMCL0(9 genes,2 taxa): G001|7000003252690302(G001) G001|7000003252690305(G001) G001|7000003252690389(G001) G001|7000003252690392(G001) G003|7000003071119023(G003) G003|7000003071119026(G003) G003|7000003071120910(G003) G003|7000003071120913(G003) G003|7000003071120922(G003)
	#ORTHOMCL1(6 genes,2 taxa): G001|7000003252690296(G001) G001|7000003252690395(G001) G003|7000003071119029(G003) G003|7000003071119032(G003) G003|7000003071120919(G003) G003|7000003071120925(G003)
	open ORTS_FILE, $self->{filename} or die "Unable to open file " . $self->{filename} . "\n";
	while (my $line=<ORTS_FILE>) {
		chomp $line;
		my ($orts_num,$orts_fields) = ( $line =~ /^ORTHOMCL(\d+)[\w\W]+?\t\s([\w\W]+)/ );
		die "Error: OrthoMCL file parsing: Unrecognizable line:\n $line\n" if((!defined $orts_num) || (!defined $orts_fields));

		#push( @{ $self->{cluster_ids} }, $orts_num );

		$self->{cluster_ids_hash}{$orts_num} = 1;
		
		my @fields = split " ", $orts_fields;
		
		foreach my $curr_field (@fields) {
			my ($org_num_hex, $curr_gene) = ( $curr_field =~ /([\w\W]+?)\|([\w\W]+?)\(/ );
			$org_num_hex =~ s/^G*//;
			my $org_num = hex($org_num_hex);
			my $org_name = $self->{org_name}[$org_num];

			push( @{ $self->{orts}[$orts_num]{$org_name} }, $curr_gene );
			$self->{gene_index}{$curr_gene} = $orts_num;
			$self->{gene}{$curr_gene}       = $curr_gene;
			$self->{set}{$curr_gene}        = "Ortho";
			
			$self->{locus_name}{$curr_gene} = $curr_gene;
			$self->{transcript}{$curr_gene} = $curr_gene;			
		}
	}
	close ORTS_FILE;
}

#828547707	Ecoli_H112180280	Ecoli_H112180280_POSTPRODIGAL_2	7000006964752101	7000006964752100	None	mannose-1-phosphate guanylyltransferase 1
#828547707	Ecoli_TY_2482_BGI	Ecoli_TY_2482_BGI_POSTPRODIGAL_2	7000006964764261	7000006964764260	None	mannose-1-phosphate guanylyltransferase 1
#828547707	EscCol_55989_GBD3	EscCol_55989_GBD3_POSTPRODIGAL_1	7000006964790339	7000006964790338	None	mannose-1-phosphate guanylyltransferase 1
#828547707	Esch_coli_04-8351_V1	Esch_coli_04-8351_V1_POSTPRODIGAL_1	7000006961080847	7000006961080846	EUDG_02241	mannose-1-phosphate guanylyltransferase 1
sub read_RBH {
	my $self = shift;

	open my $fh, '<', $self->{filename} or die "Unable to open file " . $self->{filename} . "\n";
	while (my $line=<$fh>) {
		chomp $line;
		die "The cluster file " . $self->{filename} . " seems to be generated by OrthoMCL.\nPlease indicate the correct format." if ($line =~ /^ORTHOMCL/);

		next if $line =~ /^\s*$/;

		my ($orts_num, $org_name, $set, $transcript, $gene, $locus_name, $func_annot);
		if ( $self->{format} eq 'RBH_Calhoun' ) {
			($orts_num, $org_name, $set, $transcript, $gene, $locus_name, $func_annot) = split "\t", $line;
		}
		else {
			($orts_num, $set, $org_name, $transcript, $gene, $locus_name, $func_annot) = split "\t", $line;
		}

		$self->{cluster_ids_hash}{$orts_num} = 1;

		my $gene_identifier;
		if ( $self->{gene_identifying_feature} eq "transcript" ) { $gene_identifier = $transcript; }
		elsif ( $self->{gene_identifying_feature} eq "gene" ) { $gene_identifier = $gene; }
		elsif ( $self->{gene_identifying_feature} eq "locus_name" ) { $gene_identifier = $locus_name; }
		else { die "Unrecognizable gene identifying feature \'" . $self->{gene_identifying_feature} . "\'\n"; }

		#print STDERR "Orts num: $orts_num  Org name: >>>>>$org_name<<<<<    Identifier: $gene_identifier\n";
		#getc();

		push( @{ $self->{orts}[$orts_num]{$org_name} }, $gene_identifier );
		$self->{gene_index}{$gene_identifier} = $orts_num;
		$self->{gene_annot}{$gene_identifier} = $func_annot;
		$self->{locus_name}{$gene_identifier} = $locus_name;
		$self->{transcript}{$gene_identifier} = $transcript;
		$self->{gene}{$gene_identifier}       = $gene;
		$self->{set}{$gene_identifier}        = $set;
		$self->{org_num}{$org_name} = 1;
	}
	close $fh;

	# Associating a number to each organisms/genome
	my $cont_org = 0;
	foreach my $curr_org ( keys %{ $self->{org_num} } ) {
		$self->{org_num}{$curr_org} = $cont_org;
		$self->{org_name}[$cont_org] = $curr_org;
		$cont_org++;
	}
}

sub add_annotation {
	my $self = shift;

	my %all_proteins;
	my ($file_in) = @_;
	open my $fh, '<', $file_in or die "Unable to open file $file_in\n";
	while(my $line=<$fh>){
		chomp $line;
		my ($transcript,$gene_id,$locus_name,$func_annot) = split /\t/, $line;
		
		my $gene_identifier;
		if ($self->{gene_identifying_feature} eq "transcript") { $gene_identifier = $transcript; }
		elsif ($self->{gene_identifying_feature} eq "gene") { $gene_identifier = $gene_id; }
		elsif ($self->{gene_identifying_feature} eq "locus_name") { $gene_identifier = $locus_name; }
		else { die "Unrecognizable gene identifying feature \'" . $self->{gene_identifying_feature} . "\'\n"; }
		
		$self->{gene_annot}{$gene_identifier} = $func_annot;
		$self->{locus_name}{$gene_identifier} = $locus_name;
		$self->{transcript}{$gene_identifier} = $transcript;
		$self->{gene}{$gene_identifier}       = $gene_id;
	}
	close $fh;
}

sub get_gene_annot {
	my $self = shift;
	my ($gene_name) = @_;
	return $self->{gene_annot}{$gene_name};
}

sub combined_annot_cluster {
	my $self = shift;
	my ($orts_num) = @_;

	my %all_annot;
	foreach my $org_name ( keys %{ $self->{orts}[$orts_num] } ) {
		foreach my $ortholog ( @{ $self->{orts}[$orts_num]{$org_name} } ) {
			my $curr_annot = $self->{gene_annot}{$ortholog};
			$curr_annot =~ s/name="//g;
			$curr_annot =~ s/"//g;
			$all_annot{$curr_annot} = 1;
		}
	}
	return join( ' && ', keys %all_annot );
}

sub combined_annot_from_genes {
	my $self = shift;
	my ($refArrGeneName) = @_;

	my %all_annot;
	foreach my $curr_gene ( @{$refArrGeneName} ) {
		my $curr_annot = $self->{gene_annot}{$curr_gene};
		$curr_annot =~ s/name="//g;
		$curr_annot =~ s/"//g;

		$all_annot{$curr_annot} = 1;
	}

	return join( ' && ', keys %all_annot );
}

sub get_orgs {
	my $self = shift;
	return @{ $self->{org_name} };
}

sub get_cluster_ids {
	my $self = shift;
	return @{ $self->{cluster_ids} };
}

sub get_org_name {
	my $self = shift;
	my ($org_num) = @_;
	return $self->{org_name}[$org_num];
}

sub get_org_num {
	my $self = shift;
	my ($org_name) = @_;

	return -1 if not defined $self->{org_num}{$org_name};

	return $self->{org_num}{$org_name};
}

sub get_num_orgs {
	my $self = shift;
	return scalar( @{ $self->{org_name} } );
}

sub get_orts {
	my $self = shift;
	my ( $gene_name, $org_name ) = @_;

	my $orts_num = $self->{gene_index}{$gene_name};

	#print STDERR "Org name. $org_name Orts num:" . $orts_num . "\n";
	if ( not defined($orts_num) ) {
		#print STDERR "Not able to find gene >>>$gene_name<<< in the ortholog clusters file.\n";
		return "";
	}
	elsif ( not defined( $self->{orts}[$orts_num]{$org_name} ) ) {
		#print STDERR "Not able to find orthologs of >>>$org_name<<< on cluster num. $orts_num\n";
		return "";
	}
	elsif ( not defined( $self->get_org_num($org_name) ) ) {
		#print STDERR "Genome >>>$org_name<<< not found in the ortholog clusters file.\n";
		return "";
	}

	return @{ $self->{orts}[$orts_num]{$org_name} };
}

sub get_core {
	my $self = shift;
	my ( $gene_name, $org_name ) = @_;
	my $orts_num = -1;
	$orts_num = $self->{gene_index}{$gene_name};
	if ( $orts_num == -1 || not defined( $self->{orts}[$orts_num]{$org_name})) {
		warn "Not able to find ortholog of gene $gene_name on $org_name\n";
		return 0;
	}
	return @{ $self->{orts}[$orts_num]{$org_name} };
}

sub get_cluster_desc_repo_format {
	my $self = shift;
	my ($orts_num) = @_;

	my $content = '';
	my %all_annot;
	foreach my $org_name ( keys %{ $self->{orts}[$orts_num] } ) {
		#die "what is my $org_name\n";
		foreach my $ortholog ( @{ $self->{orts}[$orts_num]{$org_name} } ) {
			my $curr_annot = $self->{gene_annot}{$ortholog};
			$curr_annot =~ s/name="//g;
			$curr_annot =~ s/"//g;
			my $locus_name = $self->{locus_name}{$ortholog};
			my $transcript = $self->{transcript}{$ortholog};
			my $gene       = $self->{gene}{$ortholog};
			my $set        = $self->{set}{$ortholog};
			$content .= join("\t", ($orts_num, $org_name, $set, $transcript, $gene, $locus_name, $curr_annot)) . "\n";
		}
	}
	return $content;
}

sub print_cluster {
	my $self = shift;
	my ($gene_name) = @_;

	my $orts_num = $self->{gene_index}{$gene_name};

	#print STDERR "Org name. $org_name Orts num:" . $orts_num . "\n";
	if ( not defined($orts_num) ) {
		warn "Not able to find gene >>>$gene_name<<< in the ortholog clusters file.\n";
	}

	foreach my $org_name ( keys %{ $self->{orts}[$orts_num] } ) {
		print "Org: $org_name\n";
		foreach my $ortholog ( @{ $self->{orts}[$orts_num]{$org_name} } ) {
			print "\t$ortholog\n";
		}
	}
}

sub get_orts_by_cluster_num_org {
	my $self = shift;
	my ($orts_num, $org_name) = @_;

	#print STDERR "Org name. $org_name Orts num:" . $orts_num . "\n";
	if ( not defined( $self->{orts}[$orts_num]{$org_name} ) ) {
		#warn "Not able to find ortholog on $org_name for cluster $orts_num\n";
		return 0;
	}

	return @{ $self->{orts}[$orts_num]{$org_name} };
}

sub has_at_least_one_ort {
	my $self = shift;
	my ($gene_name, $orgs_list) = @_;
	if (defined $orgs_list) {
		my @orgs = split ":", $orgs_list;
		foreach my $curr_org (@orgs) {
			return 1 if $self->get_orts( $gene_name, $curr_org ) ne '';
		}
	} else {
		foreach my $curr_org ( $self->get_orgs() ) {
			return 1 if $self->get_orts( $gene_name, $curr_org ) ne '';
		}
	}
	return 0;
}

return 1;
