//
// Check input samplesheet and get read channels
//

params.options = [:]

include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check' addParams( options: params.options )

workflow INPUT_CHECK {
    take:
    samplesheet // file  : /path/to/samplesheet.csv
    platform    // string: sequencing platform. Accepted values: 'illumina', 'nanopore'

    main:
    SAMPLESHEET_CHECK ( samplesheet, platform )

    if (platform == 'illumina') {
        SAMPLESHEET_CHECK
            .out
            .csv
            .splitCsv ( header:true, sep:',' )
            .map { create_fastq_channels(it) }
            .set { sample_info }
    } else if (platform == 'nanopore') {
        SAMPLESHEET_CHECK
            .out
            .csv
            .splitCsv ( header:true, sep:',' )
            .map { row -> [ row.barcode, row.sample ] }
            .set { sample_info }
    }

    

    emit:
    sample_info // channel: [ val(meta), [ reads ] ]
    versions = SAMPLESHEET_CHECK.out.versions // channel: [ versions.yml ]
}

// Function to get list of [ meta, [ fastq_1, fastq_2 ] ]
def create_fastq_channels(LinkedHashMap row) {
    def meta = [:]
    meta.id           = row.sample
    meta.single_end   = row.single_end.toBoolean()
    def array = []
    if (!file(row.fastq_1).exists()) {
        exit 1, "ERROR: Please check input samplesheet -> Read 1 FastQ file does not exist!\n${row.fastq_1}"
    }
    if (meta.single_end) {
        array = [ meta, [ file(row.fastq_1) ] ]
    } else {
        if (!file(row.fastq_2).exists()) {
            exit 1, "ERROR: Please check input samplesheet -> Read 2 FastQ file does not exist!\n${row.fastq_2}"
        }
        array = [ meta, [ file(row.fastq_1), file(row.fastq_2) ] ]
    }
    return array
}
