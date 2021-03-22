/*
 * Diversity indices with QIIME2
 */

params.filterasv_options = [:]
params.ancom_tax_options = [:]
params.ancom_asv_options = [:]

include { QIIME2_FILTERASV                 } from '../../modules/local/qiime2_filterasv'  addParams( options: params.filterasv_options )
include { QIIME2_ANCOM_TAX                 } from '../../modules/local/qiime2_ancom_tax'  addParams( options: params.ancom_tax_options )
include { QIIME2_ANCOM_ASV                 } from '../../modules/local/qiime2_ancom_asv'  addParams( options: params.ancom_asv_options )

workflow QIIME2_ANCOM {
    take:
    ch_metadata
	ch_asv
    ch_metacolumn_all
    ch_tax
    
    main:	
    //Filter ASV table to get rid of samples that have no metadata values
    //TODO: this part might benefit also other subworkflows/processes, such as QIIME2_DIVERSITY_ALPHA & BETA & BETAORD, but only when .getVal() works again (not in 21.0{2,3}.0-edge), because the error below seems not optimal
    QIIME2_FILTERASV ( ch_metadata, ch_asv, ch_metacolumn_all )
    //Print warning & error if no filtered output was produced
    QIIME2_FILTERASV.out.qza.subscribe { 
        if ( it.baseName.toString().startsWith("WARNING") ) { 
            log.warn "ANCOM cannot work without proper metadata categories. Please (a) choose other metadata or (b) use --skip_ancom."
            exit 1, it.baseName.toString().replace("WARNING ","QIIME2_FILTERASV: ") 
        }
    }

    //ANCOM on various taxonomic levels
    ch_taxlevel = Channel.from( 2, 3, 4, 5, 6 )
    ch_metadata
        .combine( QIIME2_FILTERASV.out.qza.flatten() )
        .combine( ch_tax )
        .combine( ch_taxlevel )
        .set{ ch_for_ancom_tax }
    QIIME2_ANCOM_TAX ( ch_for_ancom_tax )

    QIIME2_ANCOM_ASV ( ch_metadata.combine( QIIME2_FILTERASV.out.qza.flatten() ) )
}