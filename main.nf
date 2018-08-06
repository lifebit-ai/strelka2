
//============================================================================================================================
//        PARAMETERS
//============================================================================================================================


/*--------------------------------------------------
  Fasta related input files
  You can use the flag --hg19 for using the hg19 version of the Genome.
  You can use the flag --h38 for using the GRCh38.p10 version of the Genome.
  They can be passed manually, through the parameter:
  	params.fasta="/my/path/to/file";
  And if already at user's disposal ( if not, automatically generated ):
	params.fai="/my/path/to/file";
	params.fastagz="/my/path/to/file";
	params.gzfai="/my/path/to/file";
	params.gzi="/my/path/to/file";
  if no input is given, the hg19 version of the genome is used.
---------------------------------------------------*/
params.hg19="true";
params.h38="";
params.test="";

params.fasta="nofasta";
params.fai="nofai";
params.fastagz="nofastagz";
params.gzfai="nogzfai";
params.gzi="nogzi";

if(!("nofasta").equals(params.fasta)){
  fasta=file(params.fasta)
  fai=file(params.fai);
  fastagz=file(params.fastagz);
  gzfai=file(params.gzfai);
  gzi=file(params.gzi);
}
else if(params.h38 ){
  fasta=file("s3://deepvariant-data/genomes/h38/GRCh38.p10.genome.fa");
  fai=file("s3://deepvariant-data/genomes/h38/GRCh38.p10.genome.fa.fai");
  fastagz=file("s3://deepvariant-data/genomes/h38/GRCh38.p10.genome.fa.gz");
  gzfai=file("s3://deepvariant-data/genomes/h38/GRCh38.p10.genome.fa.gz.fai");
  gzi=file("s3://deepvariant-data/genomes/h38/GRCh38.p10.genome.fa.gz.gzi");
}
else if(params.test ){
  fasta=file("s3://deepvariant-test/input/ucsc.hg19.chr20.unittest.fasta");
  fai=file("s3://deepvariant-test/input//ucsc.hg19.chr20.unittest.fasta.fai");
  fastagz=file("s3://deepvariant-test/input/ucsc.hg19.chr20.unittest.fasta.gz");
  gzfai=file("s3://deepvariant-test/input/ucsc.hg19.chr20.unittest.fasta.gz.fai");
  gzi=file("s3://deepvariant-test/input/ucsc.hg19.chr20.unittest.fasta.gz.gzi");
}
else if(params.hg19 ){
  fasta=file("s3://deepvariant-data/genomes/hg19/hg19.fa");
  fai=file("s3://deepvariant-data/genomes/hg19/hg19.fa.fai");
  fastagz=file("s3://deepvariant-data/genomes/hg19/hg19.fa.gz");
  gzfai=file("s3://deepvariant-data/genomes/hg19/hg19.fa.gz.fai");
  gzi=file("s3://deepvariant-data/genomes/hg19/hg19.fa.gz.gzi");
}
else{
  System.out.println(" --fasta \"/path/to/your/genome\"  params is required and was not found! ");
  System.out.println(" or you can use standard genome versions by typing --hg19 or --h38 ");
  System.exit(0);
}

int cores = Runtime.getRuntime().availableProcessors();
params.j=cores



/*--------------------------------------------------
  Params for the Read Group Line to be added just in
  case its needed.
  If not given, default values are used.
---------------------------------------------------*/
params.rgid=4;
params.rglb="lib1";
params.rgpl="illumina";
params.rgpu="unit1";
params.rgsm=20;

/*--------------------------------------------------
  Bam input files
  The input must be a path to a folder containing multiple bam files
---------------------------------------------------*/
params.bam_folder="s3://deepvariant-test/input/";
Channel.fromPath("${params.bam_folder}/*.bam").map{ file -> tuple(file.name, file) }.set{bamChannel}



/*--------------------------------------------------
  Output directory
---------------------------------------------------*/
params.resultdir = "Results";

//============================================================================================================================
//        PROCESSES
//============================================================================================================================

/******
*
*   PREPROCESSING:
*
*   1A Preprocessing Genome
*     - Index and compress the genome ( Create fa.fai, fa.gz, fa.gz.fai, fa.gz.gzi and the dict file )
*
*   1B Preprocessing Bams
*     - Add RG line in case it is missing
*     - Reorder Bam
*     - Index Bam
*
*
*****/

process preprocess_genome{

  container 'lifebitai/samtools'


  input:
  file fasta from fasta
  file fai from fai
  file fastagz from fastagz
  file gzfai from gzfai
  file gzi from gzi
  output:
  set file(fasta),file("${fasta}.fai"),file("${fasta}.gz"),file("${fasta}.gz.fai"), file("${fasta}.gz.gzi"),file("${fasta.baseName}.dict") into fastaChannel
  script:
  """
  [[ $fai == "nofai" ]] &&  samtools faidx $fasta || echo " fai file of user is used, not created"
  [[ $fastagz == "nofastagz" ]]  && bgzip -c ${fasta} > ${fasta}.gz || echo "fasta.gz file of user is used, not created "
  [[ $gzfai == "nogzi" ]] && bgzip -c -i ${fasta} > ${fasta}.gz || echo "gzi file of user is used, not created"
  [[ $gzi == "nogzfai" ]] && samtools faidx "${fasta}.gz" || echo "gz.fai file of user is used, not created"
  PICARD=`which picard.jar`
  java -jar \$PICARD CreateSequenceDictionary R= $fasta O= ${fasta.baseName}.dict
  """
}


process preprocess_bam{

  tag "${bam[0]}"
  container 'lifebitai/samtools'


  input:
  set val(prefix), file(bam) from bamChannel
  set file(genome),file(genomefai),file(genomegz),file(genomegzfai),file(genomegzgzi),file(genomedict) from fastaChannel

  output:
  set file("ready/ordered/${bam[0]}"), file("ready/ordered/${bam[0]}.bai") into completeChannel

  script:
  """
  PICARD=`which picard.jar`
  ## Add RG line in case it is missing
    mkdir ready
    [[ `samtools view -H ${bam[0]} | grep '@RG' | wc -l`   > 0 ]] && { mv $bam ready; }|| { java -jar  \$PICARD  AddOrReplaceReadGroups \
    I=${bam[0]} O=ready/${bam[0]} RGID=${params.rgid} RGLB=${params.rglb} RGPL=${params.rgpl} RGPU=${params.rgpu} RGSM=${params.rgsm}; }
  ## Reorder Bam file
    cd ready; mkdir ordered;  java -jar \$PICARD  ReorderSam I=${bam[0]} O=ordered/${bam[0]} ALLOW_INCOMPLETE_DICT_CONCORDANCE=true R=../$genome ;
  ## Index Bam file
    cd ordered ; samtools index ${bam[0]};
  """

}


//Preparing channel ( pairing fasta with bams)
fastaChannel.map{file -> tuple (1,file[0],file[1],file[2],file[3],file[4],file[5])}
              .set{all_fa};

completeChannel.map { file -> tuple(1,file[0],file[1]) }
                 .set{all_bam};

all_fa.cross(all_bam)
        .set{all_fa_bam};

//all_fa_bam.subscribe{ println it };


/******
*
*   VARIANT CALLING
*
*****/

process run_variant_caller {

    tag "${bam[1]}"
    container "lifebitai/strelka2"
    publishDir "$baseDir/${params.resultdir}"
    cpus params.j

    input:
    set file(fasta), file(bam) from all_fa_bam

    output:
    file('calling_output.vcf') into methods_result

    script:
    """
    	pwd=\$PWD

	/strelka-2.9.4.centos6_x86_64/bin/configureStrelkaGermlineWorkflow.py \
	 --bam NA12878_S1.chr20.10_10p1mb.bam \
	 --ref ucsc.hg19.chr20.unittest.fasta  \
	 --runDir ~/demo_germline

	cd ~/demo_germline

	./runWorkflow.py -j ${params.j} -m local 

	cd ./results/variants/

	gunzip ./variants.vcf.gz

	mv variants.vcf \$pwd/calling_output.vcf
    """
}



workflow.onComplete {
    println ( workflow.success ? "Done! \nYou can find your results in $baseDir/${params.resultdir}" : "Oops .. something went wrong" )
}
