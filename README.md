```
░█████╗░██╗██╗░░░██╗░██████╗███████╗███████╗██╗░░██╗███████╗██████╗░
██╔══██╗██║██║░░░██║██╔════╝██╔════╝██╔════╝██║░██╔╝██╔════╝██╔══██╗
███████║██║╚██╗░██╔╝╚█████╗░█████╗░░█████╗░░█████═╝░█████╗░░██████╔╝
██╔══██║██║░╚████╔╝░░╚═══██╗██╔══╝░░██╔══╝░░██╔═██╗░██╔══╝░░██╔══██╗
██║░░██║██║░░╚██╔╝░░██████╔╝███████╗███████╗██║░╚██╗███████╗██║░░██║
╚═╝░░╚═╝╚═╝░░░╚═╝░░░╚═════╝░╚══════╝╚══════╝╚═╝░░╚═╝╚══════╝╚═╝░░╚═╝ 
```

# nf-aivseeker

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A521.04.0-23aa62.svg?labelColor=000000)](https://www.nextflow.io/)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)


## Introduction

The application of next generation sequencing (NGS) in infectious disease surveillance and outbreak investigations has become a promising area. Environmental sampling provides a method to collect and identify potentially dangerous pathogens that are circulating in an animal population, however detection of a low-abundance pathogen target in a large metagenomic background is still a challenge. **AIV_seeker** pipeline that is optimized for detecting and identifying low-abundance avian influenza virus (AIV) from metagenomic NGS data.

The workfow was originally built in Perl, but now we decided to switch to [Nextflow](https://www.nextflow.io)-[DSL2](https://www.nextflow.io/docs/latest/dsl2.html) as workflow engine starting from version 0.3. Nextflow makes the pipeline more scalable and reproducible. It's easy to run tasks across multiple compute infrastructures, and also it can support `conda`/`Docker`/`Singularity` containers making installation trivial and results highly reproducible. 

A detailed structure and each module of the workflow is presented below in the dataflow diagram.

## Pipeline summary

![aiv_seeker_workflow](docs/aiv_seeker_workflow.jpg)

The pipeline currently takes reads from metagenomics sequencing as the starting point, then does a QC check. It performs quality trims the reads and adapters with [fastp](https://github.com/OpenGene/fastp), and performs basic QC with [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/) and summerize the QC QC results with [MultiQC](https://multiqc.info/). You can also get a quick taxonomic report with [Krakne2](https://github.com/DerrickWood/kraken2) or [Centrifugre](https://ccb.jhu.edu/software/centrifuge) by setting `skip_kraken2=false` or `--skip_centrifuge=false`.

The pipeline then preprocesses the sequences by merging pair-end reads with [Vsearch: mergepairs](https://github.com/torognes/vsearch), performing quality filtering with [Vsearch: fasta_filter](https://github.com/torognes/vsearch) and dereplication with [Vsearch: derep_fulllength](https://github.com/torognes/vsearch).

After preprocessing, it performs two rounds of alignments to balance running time and accuracy. The first round is done with [Diamond](https://github.com/bbuchfink/diamond), then the second run is done with [BLAST](https://blast.ncbi.nlm.nih.gov/Blast.cgi?PAGE_TYPE=BlastDocs&DOC_TYPE=Download). 

Furthermore, the pipeline creates reports in the results directory specified, summarizing some of the subtyping results and sequences.


## Quick Start

1. Install [`nextflow`](https://nf-co.re/usage/installation) (`>=20.04.0`)

2. Install [`Docker`](https://docs.docker.com/engine/installation/), [`Singularity`](https://www.sylabs.io/guides/3.0/user-guide/) or [`Conda`](https://conda.io/miniconda.html)

3. Download the pipeline and test it on a demo dataset with a single command:

 ```bash
    nextflow run cidgoh/AIV_seeker -profile singualrity --input demo_data/samplesheet.csv
 ```

4. Start running your own analysis!

5. Once your run has completed successfully, clean up the intermediate files.

```bash
    nextflow clean -f -k
 ```

## Support

For further information or help, don't hesitate to get in touch at 
[jun_duan@sfu.ca](mailto:jun_duan@sfu.ca) or [wwshiao@sfu.ca](mailto:wwshiao@sfu.ca)

## Citations
An extensive list of references for the tools used by the workflow 
can be found in the [CITATIONS.md](https://github.com/cidgoh/AIV_seeker/blob/dev_nf-aivseeker/docs/CITATIONS.md) file.
