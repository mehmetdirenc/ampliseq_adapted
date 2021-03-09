////////////////////////////////////////////////////
/* --         LOCAL PARAMETER VALUES           -- */
////////////////////////////////////////////////////

params.summary_params = [:]

////////////////////////////////////////////////////
/* --          VALIDATE INPUTS                 -- */
////////////////////////////////////////////////////

/*
 * Import input files
 */
if (params.metadata) {
	ch_metadata = Channel.fromPath("${params.metadata}", checkIfExists: true)
} else { ch_metadata = Channel.empty() }

if (params.classifier) {
	ch_qiime_classifier = Channel.fromPath("${params.classifier}", checkIfExists: true)
} else { ch_qiime_classifier = Channel.empty() }

if( params.tax_to_classifier && params.fasta_to_classifier && !params.onlyDenoising && !params.skip_taxonomy ){
	ch_fasta_to_classifier = Channel.fromPath("${params.fasta_to_classifier}", checkIfExists: true)
	ch_tax_to_classifier = Channel.fromPath("${params.tax_to_classifier}", checkIfExists: true)
} else { 
	ch_fasta_to_classifier = Channel.empty()
	ch_tax_to_classifier = Channel.empty()
}

if (params.dada_ref_taxonomy && !params.onlyDenoising) {
	ch_dada_ref_taxonomy = Channel.fromPath("${params.dada_ref_taxonomy}", checkIfExists: true)
} else { ch_dada_ref_taxonomy = Channel.empty() }

if (params.dada_ref_species && params.dada_ref_taxonomy && !params.onlyDenoising) {
	ch_dada_ref_species = Channel.fromPath("${params.dada_ref_species}", checkIfExists: true)
} else { ch_dada_ref_species = Channel.empty() }

/*
 * Set variables
 */

single_end = params.pacbio ? true : params.single_end

trunclenf = params.trunclenf ? params.trunclenf : 0 
trunclenr = params.trunclenr ? params.trunclenr : 0
if (!single_end && !params.illumina_its && (params.trunclenf == false || params.trunclenr == false) ) {
	log.warn "No DADA2 cutoffs were specified (--trunclenf & --trunclenr), therefore reads will be truncated where median quality drops below ${params.trunc_qmin} (defined by --trunc_qmin) but at least a fraction of ${params.trunc_rmin} (defined by --trunc_rmin) of the reads will be retained.\nThe chosen cutoffs do not account for required overlap for merging, therefore DADA2 might have poor merging efficiency or even fail.\n"
}

/*
 * Sanity check input values
 */

if (params.enable_conda) { log.warn "Conda is enabled (--enable_conda), any steps involving QIIME2 are not available. Use a container engine instead of conda to enable all software." }

if (!params.FW_primer) { exit 1, "Option --FW_primer missing" }
if (!params.RV_primer) { exit 1, "Option --RV_primer missing" }
if (!params.input) { exit 1, "Option --input missing" }

//TRUE, FALSE, pseudo allowed, see https://benjjneb.github.io/dada2/pseudo.html#Pseudo-pooling
if (!["pooled", "independent", "pseudo"].contains(params.sample_inference)) {
	exit 1, "Please set --sample_inference to one of the following:\n\t-\"independent\" (lowest sensitivity and lowest resources),\n\t-\"pseudo\" (balance between required resources and sensitivity),\n\t-\"pooled\" (highest sensitivity and resources)."
}

if (params.double_primer && params.retain_untrimmed) { 
	exit 1, "Incompatible parameters --double_primer and --retain_untrimmed cannot be set at the same time."
}

if (!params.classifier){
        if (!(params.taxon_reference == 'silva' || params.taxon_reference == 'unite')) exit 1, "--taxon_reference need to be set to either 'silva' or 'unite'"
}

////////////////////////////////////////////////////
/* --          CONFIG FILES                    -- */
////////////////////////////////////////////////////

ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yaml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config) : Channel.empty()

////////////////////////////////////////////////////
/* --    IMPORT LOCAL MODULES/SUBWORKFLOWS     -- */
////////////////////////////////////////////////////

// Don't overwrite global params.modules, create a copy instead and use that within the main script.
def modules = params.modules.clone()

def dada2_filtntrim_options = modules['dada2_filtntrim']
dada2_filtntrim_options.args       += single_end ? ", maxEE = $params.maxEE" : ", maxEE = c($params.maxEE, $params.maxEE)"
if (params.pacbio) {
	//PacBio data
	dada2_filtntrim_options.args   +=", minLen = $params.minLen, maxLen = $params.maxLen, rm.phix = FALSE"
} else if (params.illumina_its) {
	//Illumina ITS data or other sequences with high length variability
	dada2_filtntrim_options.args   += ", minLen = $params.minLen, maxLen = $params.maxLen, rm.phix = TRUE"
} else {
	//Illumina 16S data
	dada2_filtntrim_options.args   += ", minLen = $params.minLen, maxLen = $params.maxLen, rm.phix = TRUE"
}

def dada2_quality_options = modules['dada2_quality'] 

def trunclen_options = [:]
trunclen_options.args       ="$params.trunc_qmin $params.trunc_rmin"

//TODO: adjust for single_end & PacBio
def dada2_err_options = modules['dada2_err']
dada2_err_options.args   += params.pacbio ? ", errorEstimationFunction = PacBioErrfun" : ", errorEstimationFunction = loessErrfun"

def dada2_denoising_options = modules['dada2_denoising']
dada2_denoising_options.args         += params.sample_inference == "pseudo" ? ", pool = \"pseudo\"" : params.sample_inference == "pooled" ? ", pool = TRUE" : ", pool = FALSE"

def dada2_rmchimera_options = modules['dada2_rmchimera']

def multiqc_options         = modules['multiqc']
multiqc_options.args       += params.multiqc_title ? " --title \"$params.multiqc_title\"" : ''

def dada2_taxonomy_options  = modules['dada2_taxonomy']
dada2_taxonomy_options.args += params.pacbio ? ", tryRC = TRUE" : ""

def dada2_addspecies_options  = modules['dada2_addspecies']
dada2_addspecies_options.args += params.pacbio ? ", tryRC = TRUE" : ""

include { PARSE_INPUT                   } from './modules/local/subworkflow/parse_input'              addParams( options: [:]                             )
include { RENAME_RAW_DATA_FILES         } from './modules/local/process/rename_raw_data_files'
include { DADA2_FILTNTRIM               } from './modules/local/process/dada2'                        addParams( options: dada2_filtntrim_options         )
include { DADA2_QUALITY                 } from './modules/local/process/dada2'                        addParams( options: dada2_quality_options           )
include { TRUNCLEN                      } from './modules/local/process/trunclen'                     addParams( options: trunclen_options                )
include { DADA2_ERR                     } from './modules/local/process/dada2'                        addParams( options: dada2_err_options               )
include { DADA2_DEREPLICATE             } from './modules/local/process/dada2'                        addParams( options: modules['dada2_dereplicate']    )
include { DADA2_DENOISING               } from './modules/local/process/dada2'                        addParams( options: dada2_denoising_options         )
include { DADA2_RMCHIMERA               } from './modules/local/process/dada2'                        addParams( options: dada2_rmchimera_options         )
include { DADA2_STATS                   } from './modules/local/process/dada2'                        addParams( options: modules['dada2_stats']          )
include { DADA2_MERGE                   } from './modules/local/process/dada2'                        addParams( options: modules['dada2_merge']          )
include { DADA2_TAXONOMY                } from './modules/local/process/dada2'                        addParams( options: dada2_taxonomy_options          )
include { DADA2_ADDSPECIES              } from './modules/local/process/dada2'                        addParams( options: dada2_addspecies_options        )
include { QIIME2_PREPTAX                } from './modules/local/subworkflow/qiime2_preptax'           addParams( options: modules['qiime2_preptax']       )
include { QIIME2_TAXONOMY               } from './modules/local/subworkflow/qiime2_taxonomy'          addParams( options: modules['qiime2_taxonomy']      )
include { QIIME2_INSEQ                  } from './modules/local/process/qiime2'                       addParams( options: modules['qiime2_inseq']         )
include { QIIME2_FILTERTAXA             } from './modules/local/process/qiime2'                       addParams( options: modules['qiime2_filtertaxa']    )
include { QIIME2_INASV                  } from './modules/local/process/qiime2'                       addParams( options: modules['qiime2_inasv']         )
include { FILTER_STATS                  } from './modules/local/process/filter_stats'                 addParams( options: modules['filter_stats']         )
include { QIIME2_BARPLOT                } from './modules/local/process/qiime2'                       addParams( options: modules['qiime2_barplot']       )
include { QIIME2_EXPORT                 } from './modules/local/subworkflow/qiime2_export'            addParams( absolute_options: modules['qiime2_export_absolute'], relasv_options: modules['qiime2_export_relasv'],reltax_options: modules['qiime2_export_reltax'],combine_table_options: modules['combine_table']         )
include { QIIME2_INTAX                  } from './modules/local/process/qiime2'                       addParams( options: modules['qiime2_intax']         )
include { MULTIQC                       } from './modules/local/process/multiqc'                      addParams( options: multiqc_options                 )
include { GET_SOFTWARE_VERSIONS         } from './modules/local/process/get_software_versions'        addParams( options: [publish_files : ['csv':'']]    )

/*
 * SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
 */

 //TODO

 ////////////////////////////////////////////////////
/* --    IMPORT NF-CORE MODULES/SUBWORKFLOWS   -- */
////////////////////////////////////////////////////

/*
 * MODULE: Installed directly from nf-core/modules
 */
def fastqc_options              = modules['fastqc']

//TODO: add another option: params.illumina_its which should be "-g ${params.FW_primer} -a ${params.RV_primer_RevComp} -G ${params.RV_primer} -A ${params.FW_primer_RevComp} -n 2"
//TODO: probably when params.illumina_its than also params.retain_untrimmed, have to test
def cutadapt_options_args       = !single_end ? " -g ${params.FW_primer} -G ${params.RV_primer}" : params.pacbio ? " --rc -g ${params.FW_primer}...${params.RV_primer}" : " -g ${params.FW_primer}"
def cutadapt_options 			= modules['cutadapt']
cutadapt_options.args          += cutadapt_options_args
cutadapt_options.args          += params.retain_untrimmed ? '' : " --discard-untrimmed"
def cutadapt_2nd_options        = [:]
cutadapt_2nd_options.args       = cutadapt_options_args
cutadapt_2nd_options.args      += " --discard-trimmed"
cutadapt_2nd_options.suffix     = "_double-primer"
cutadapt_2nd_options.publish_files = ['log':'']

//include { MULTIQC } from './modules/nf-core/software/multiqc/main' addParams( options: multiqc_options    )
include { FASTQC } from './modules/nf-core/software/fastqc/main' addParams( options: fastqc_options    )
include { CUTADAPT } from './modules/nf-core/software/cutadapt/main' addParams( options: cutadapt_options    )
include { CUTADAPT as CUTADAPT_2ND } from './modules/nf-core/software/cutadapt/main' addParams( options: cutadapt_2nd_options    )

/*
 * SUBWORKFLOW: Consisting entirely of nf-core/modules
 */

 ////////////////////////////////////////////////////
/* --           RUN MAIN WORKFLOW              -- */
////////////////////////////////////////////////////

// Info required for completion email and summary
def multiqc_report      = []

workflow AMPLISEQ {

	/*
	* Create a channel for input read files
	*/
	PARSE_INPUT ( params.input, single_end, params.multipleSequencingRuns, params.extension )
	ch_reads = PARSE_INPUT.out.reads
	ch_fasta = PARSE_INPUT.out.fasta

    /*
     * MODULE: Rename files
     */
	RENAME_RAW_DATA_FILES ( ch_reads )

    /*
     * MODULE: FastQC
     */
    if (!params.skip_fastqc) {
        FASTQC ( RENAME_RAW_DATA_FILES.out ).html.set { fastqc_html }
    }
    ch_software_versions = Channel.empty()
    ch_software_versions = ch_software_versions.mix(FASTQC.out.version.first().ifEmpty(null))

    /*
     * MODULE: Cutadapt
     */
    CUTADAPT ( RENAME_RAW_DATA_FILES.out ).reads.set { ch_trimmed_reads }
    ch_software_versions = ch_software_versions.mix(CUTADAPT.out.version.first().ifEmpty(null))

	if (params.double_primer) {
		CUTADAPT_2ND ( ch_trimmed_reads ).reads.set { ch_trimmed_reads }
	}

    /*
     * SUBWORKFLOW / MODULES : ASV generation with DADA2
     */
	//plot aggregated quality profile for forward and reverse reads separately
	if (single_end) {
		ch_trimmed_reads
			.map { meta, reads -> [ reads ] }
			.collect()
			.map { reads -> [ "single_end", reads ] }
			.set { ch_all_trimmed_reads }
	} else {
		ch_trimmed_reads
			.map { meta, reads -> [ reads[0] ] }
			.collect()
			.map { reads -> [ "FW", reads ] }
			.set { ch_all_trimmed_fw }
		ch_trimmed_reads
			.map { meta, reads -> [ reads[1] ] }
			.collect()
			.map { reads -> [ "RV", reads ] }
			.set { ch_all_trimmed_rv }
		ch_all_trimmed_fw
			.mix ( ch_all_trimmed_rv )
			.set { ch_all_trimmed_reads }
	}
	DADA2_QUALITY ( ch_all_trimmed_reads )
	
	//find truncation values in case they are not supplied
	if (!single_end && !params.illumina_its && (params.trunclenf == false || params.trunclenr == false) ) {
		TRUNCLEN ( DADA2_QUALITY.out.tsv )
		TRUNCLEN.out
			.toSortedList()
			.set { ch_trunc }
	} else { 
		Channel.from( [['FW', trunclenf], ['RV', trunclenr]] )
			.toSortedList()
			.set { ch_trunc }
	}
	ch_trimmed_reads.combine(ch_trunc).set { ch_trimmed_reads }

	//filter reads
	DADA2_FILTNTRIM ( ch_trimmed_reads )
	ch_software_versions = ch_software_versions.mix(DADA2_FILTNTRIM.out.version.first().ifEmpty(null))

	//group by sequencing run
	DADA2_FILTNTRIM.out.reads
		.map {
			info, reads ->
				def meta = [:]
				meta.run = info.run
				meta.single_end = info.single_end
				[ meta, reads, info.id ] }
		.groupTuple(by: 0 )
		.map {
			info, reads, ids ->
				def meta = [:]
				meta.run = info.run
				meta.single_end = info.single_end
				meta.id = ids.flatten().sort()
				[ meta, reads.flatten().sort() ] }
		.set { ch_filt_reads }

	DADA2_ERR ( ch_filt_reads )

	DADA2_DEREPLICATE ( ch_filt_reads )

	//group by meta
	DADA2_DEREPLICATE.out.dereplicated
		.join( DADA2_ERR.out.errormodel )
		.set { ch_derep_errormodel }
	DADA2_DENOISING ( ch_derep_errormodel  )

	DADA2_RMCHIMERA ( DADA2_DENOISING.out.seqtab )

	//group by sequencing run & group by meta
	DADA2_FILTNTRIM.out.log
		.map {
			info, reads ->
				def meta = [:]
				meta.run = info.run
				meta.single_end = info.single_end
				[ meta, reads, info.id ] }
		.groupTuple(by: 0 )
		.map {
			info, reads, ids ->
				def meta = [:]
				meta.run = info.run
				meta.single_end = info.single_end
				meta.id = ids.flatten().sort()
				[ meta, reads.flatten().sort() ] }
		.join( DADA2_DENOISING.out.denoised )
		.join( DADA2_DENOISING.out.mergers )
		.join( DADA2_RMCHIMERA.out.rds )
		.set { ch_track_numbers }
	DADA2_STATS ( ch_track_numbers )

	//merge if several runs, otherwise just publish
	DADA2_MERGE ( 
		DADA2_STATS.out.stats.map { meta, stats -> stats }.collect(), 
		DADA2_RMCHIMERA.out.rds.map { meta, rds -> rds }.collect() )

    /*
     * SUBWORKFLOW / MODULES : Taxonomic classification with DADA2 and/or QIIME2
     */
	//Alternative entry point for fasta that is being classified
	ch_fasta =  params.input.toString().toLowerCase().endsWith("fasta") ? ch_fasta : DADA2_MERGE.out.fasta

	//DADA2
	if (!params.onlyDenoising && !params.skip_taxonomy) {
		DADA2_TAXONOMY ( ch_fasta, ch_dada_ref_taxonomy )
		DADA2_ADDSPECIES ( DADA2_TAXONOMY.out.rds, ch_dada_ref_species )
	}

	//QIIME2
	if (!params.onlyDenoising && !params.enable_conda) {
		if (params.tax_to_classifier && params.fasta_to_classifier && !params.onlyDenoising && !params.skip_taxonomy) {
			QIIME2_PREPTAX (
				ch_fasta_to_classifier,
				ch_tax_to_classifier,
				params.FW_primer,
				params.RV_primer
			)
			ch_qiime_classifier = QIIME2_PREPTAX.out.classifier
		}
		QIIME2_TAXONOMY ( 
			ch_fasta,
			ch_qiime_classifier
		)
		ch_tax = QIIME2_TAXONOMY.out.qza
		ch_software_versions = ch_software_versions.mix( QIIME2_TAXONOMY.out.version.first().ifEmpty(null) ) //TODO: usually a .first() is here, dont know why this leads here to a warning
	}
    /*
     * SUBWORKFLOW / MODULES : Downstream analysis with QIIME2
     */
	//TODO: use QIIME2_INTAX ( DADA2_TAXONOMY.out.tsv )
	if (!params.onlyDenoising && !params.enable_conda) {
		//Import into QIIME2 & filtering by taxonomy & prevalence & counts
		QIIME2_INASV ( DADA2_MERGE.out.asv )
		QIIME2_INSEQ ( ch_fasta )
		if (params.exclude_taxa != "none" || params.min_frequency || params.min_samples) {
			QIIME2_FILTERTAXA (
					QIIME2_INASV.out.qza,
					QIIME2_INSEQ.out.qza,
					ch_tax,
					params.min_frequency,
					params.min_samples,
					params.exclude_taxa
			)
			FILTER_STATS ( DADA2_MERGE.out.asv, QIIME2_FILTERTAXA.out.tsv )
			ch_asv = QIIME2_FILTERTAXA.out.asv
			ch_seq = QIIME2_FILTERTAXA.out.seq
		} else {
			ch_asv = QIIME2_INASV.out.qza
			ch_seq = QIIME2_INSEQ.out.qza
		}
		//Export various ASV tables
		if (!params.skip_abundance_tables) {
		QIIME2_EXPORT ( ch_asv, ch_seq, ch_tax, QIIME2_TAXONOMY.out.tsv )
		}

		if (!params.skip_barplot) {
			QIIME2_BARPLOT ( ch_metadata, ch_asv, ch_tax )
		}

		//metadataCategory.r //-> required for diversities & ancom
		//metadataCategoryPairwise.r //-> required for diversities

		//Diversities
			//TREE ( ch_seq ) //-> required for diversity indices
			//alpha_rarefaction ( ch_metadata, ch_asv, QIIME2_TREE.out.qza, maxdepth=\$(count_table_minmax_reads.py "QIIME2_FILTERTAXA.out.tsv" maximum 2>&1) )
			//diversity_core ( ch_metadata, ch_asv, QIIME2_TREE.out.qza, mindepth=\$(count_table_minmax_reads.py "QIIME2_FILTERTAXA.out.tsv" minimum 2>&1) )
			//alpha_diversity ( ch_metadata, DIVERSITY_CORE.out.qza, metadataCategory.out.categories )
			//beta_diversity ( ch_metadata, DIVERSITY_CORE.out.qza, metadataCategory.out.categories )
			//beta_diversity_ordination ( ch_metadata, DIVERSITY_CORE.out.qza )
		
		//ANCOM -> samples with empty column should be removed to allow for sub-table comparisons 
			//prepare_ancom ( ch_metadata, ch_asv, metadataCategory.out.categories  )
			//ancom_tax
			//ancom_asv	
	}

    /*
     * MODULE: Pipeline reporting
     */
    GET_SOFTWARE_VERSIONS ( 
        ch_software_versions.map { it }.collect()
    )

    /*
     * MultiQC
     */
    if (!params.skip_multiqc) {
        workflow_summary    = Schema.params_summary_multiqc(workflow, params.summary_params)
        ch_workflow_summary = Channel.value(workflow_summary)

        MULTIQC (
            ch_multiqc_config,
            ch_multiqc_custom_config.collect().ifEmpty([]),
            GET_SOFTWARE_VERSIONS.out.yaml.collect(),
            ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'),
            FASTQC.out.zip.collect{it[1]}.ifEmpty([]),
            CUTADAPT.out.log.collect{it[1]}.ifEmpty([])
        )
        multiqc_report = MULTIQC.out.report.toList()
    }

}

////////////////////////////////////////////////////
/* --              COMPLETION EMAIL            -- */
////////////////////////////////////////////////////

workflow.onComplete {
    Completion.email(workflow, params, params.summary_params, projectDir, log, multiqc_report)
    Completion.summary(workflow, params, log)
}

////////////////////////////////////////////////////
/* --                  THE END                 -- */
////////////////////////////////////////////////////