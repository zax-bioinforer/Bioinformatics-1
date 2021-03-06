#!/bin/bash
# set -x

# this workflow will run bowtie on the input fastq files
# then run MACS1 and generate peaks and bedGraphs



ProjDir="/ifs/home/kellys04/projects/SmithLab_ChIPSeq_RNASeq_2016_06_01/project_notes/Combined_ChIP_RNA_Seq"
analysis_input="${ProjDir}/analysis_input"
fastq_dir="${analysis_input}/fastq2"
analysis_outdir="${ProjDir}/analysis_output"

bam_dir="${analysis_outdir}/bam"
bam_log_dir="${bam_dir}/logs"
mkdir -p "$bam_log_dir"

peaks_dir="${analysis_outdir}/peaks"
peaks_log_dir="${peaks_dir}/logs"
mkdir -p "$peaks_log_dir"


bigwig_dir="${analysis_outdir}/bigWig"
bigwig_log_dir="${bigwig_dir}/logs"
mkdir -p "$bigwig_log_dir"


# reference genome info
GENOME="hg19"
GenomeRefDir="/local/data/iGenomes/Homo_sapiens/UCSC/${GENOME}/Sequence/Bowtie2Index/genome"



cd $ProjDir
# ~~~~~~ Script Logging ~~~~~~~ #
# get the script file 
zz=$(basename $0)
# get the script dir
za=$(dirname $0)
# use either qsub job name or scriptname in log filename
mkdir -p logs/scripts
LOG_FILE=logs/scripts/scriptlog.${JOB_NAME:=$(basename $0)}.$(date -u +%Y%m%dt%H%M%S).${HOSTNAME:-$(hostname)}.$$.${RANDOM}
echo "This is the log file for the script." > $LOG_FILE
echo -e "\n pwd is:\n$PWD\n" >> $LOG_FILE
# echo -e "\nScript file is:\n$0\n" >> $LOG_FILE # for regular script usage (no qsub)
echo -e "\nScript file is:\n${JOB_NAME:=$(readlink -m $0)}\n" >> $LOG_FILE 
echo -e "\nScript file contents:\n\n%%%%%%%%%%%%%%%%%%%%%%%%%%%%" >> $LOG_FILE
cat "$0" >> $LOG_FILE
# ~~~~~~~~~~~~ #



# # make a quick sample sheet to match sample names, fastq, and inputs
# setup sample sheet
# sample_sheet="${ProjDir}/bowtie_MACS_sample-sheet.tsv"
# clear the sheet
# echo -n "" $sample_sheet
# fastq_files="$(find ${fastq_dir} -name "*.fastq.gz")"
# 
# for i in $fastq_files; do
# 	tmp_fastq="$i"
# 	echo "tmp_fastq is $tmp_fastq"
# 	
# 	# get the file name
# 	tmp_ID="$(basename $tmp_fastq)"
# 	tmp_ID="${tmp_ID%.fastq.gz}"
# 	echo "tmp_ID is $tmp_ID"
# 	
# 	# write a quick sample sheet
# 	echo -e "${tmp_ID}\t${tmp_fastq}" >> $sample_sheet
# 
# done




# NEW sample sheet:
# do quick edits in Excel to match the Inputs and set groups
sample_sheet="${ProjDir}/bowtie_MACS_sample-sheet2.tsv"
# sample sheet now has header:
# SampleID        Input   Fastq   Genome

# get the items for each from the sample
tail -n +2 $sample_sheet | while read i; do
	# echo "$i"
	if [[ ! -z "$i" ]]; then
		# echo "$i"
		tmp_ID="$(echo "$i" | cut -f1)"
		echo "$tmp_ID"
		
		tmp_input="$(echo "$i" | cut -f2)"
		echo "$tmp_input"
		
		tmp_fastq="$(echo "$i" | cut -f3)"
		echo "$tmp_fastq"
		
		tmp_out_bam_path="${bam_dir}/${tmp_ID}.bam"
		echo "$tmp_out_bam_path"
		
		# submit alignment job
		# need to hard-code the threads for the heredoc...		# THREADS=${NSLOTS:=8} 
		qsub -wd $bam_dir -o :${bam_log_dir}/ -e :${bam_log_dir}/ -pe threaded 4-12 -N "$tmp_ID" <<E0F1
			#!/bin/bash
			set -x
			
			THREADS=\${NSLOTS} 
			
			module load bowtie2/2.2.6
			module unload samtools
			module load samtools/1.2.1
			
			
			
			echo "\${THREADS} is num slots"
			echo "$tmp_ID"
			echo "$tmp_input"
			echo "$tmp_fastq"
			echo "$tmp_out_bam_path"
			
			# alignment step
			if [ ! -f ${tmp_out_bam_path} ]; then
				echo "creating alignment file"
				bowtie2 -x ${GenomeRefDir} --threads \${THREADS} --local -U ${tmp_fastq} | samtools view -Sb - > ${tmp_out_bam_path}
			fi
			
			
E0F1
		
		# set up the MACS job
		# check for NA as input 
		if [[ ! $tmp_input == "NA" ]]; then
			echo "Input isnt NA"
			echo "input is $tmp_input"
			
			# check if both bam's exist
			[ -f $tmp_out_bam_path ] && echo "Sample bam exists"
			
			# find the input bam
			tmp_input_bam="$(find $bam_dir -name "${tmp_input}.bam")"
			# make sure it exists
			[[ ! -z $tmp_input_bam ]] && [ -f $tmp_input_bam ] && echo "tmp_input_bam is $tmp_input_bam"
			
			# ID for no control MACS run
			tmp_ID_noCtrl="${tmp_ID}_noControl"
			tmp_ID_withCtrl="${tmp_ID}_withControl"
			
			# MACS job submission
			# http://liulab.dfci.harvard.edu/MACS/00README.html
			qsub -wd $peaks_dir -o :${peaks_log_dir}/ -e :${peaks_log_dir}/ -N "$tmp_ID" <<E0F2
				#!/bin/bash
				set -x
				module unload python
				module load macs/1.4.2
				echo "test"
				echo "pwd is"
				pwd
				echo "tmp_sample is $tmp_sample"
				echo "tmp_sample_bam is $tmp_sample_bam"
				echo "tmp_input_bam is $tmp_input_bam"
				
				# run nolambda w/ control bam, nolambda w/o control bam
				# compare bed files of both in IGV
				
				# macs with control no lambda
				macs14  --format=BAM --gsize=hs --nolambda --diag --name=$tmp_ID_withCtrl -t $tmp_out_bam_path -c $tmp_input_bam
				
				# macs without control no lambda
				macs14  --format=BAM --gsize=hs --nolambda --diag --name=$tmp_ID_noCtrl -t $tmp_out_bam_path 
				
				# macs regular with control
				macs14  --format=BAM --gsize=hs --bdg --single-profile --diag --name=$tmp_ID -t $tmp_out_bam_path -c $tmp_input_bam

			
E0F2
			
		fi
		
	fi
done

exit

# notes for submission of this script
this_script="/ifs/home/kellys04/projects/SmithLab_ChIPSeq_RNASeq_2016_06_01/project_notes/Combined_ChIP_RNA_Seq/code/bowtie_MACS1_BigWig_workflow2.sh"
script_name="$(basename $this_script)"
ProjDir="/ifs/home/kellys04/projects/SmithLab_ChIPSeq_RNASeq_2016_06_01/project_notes/Combined_ChIP_RNA_Seq"
log_dir="${ProjDir}/logs"; mkdir -p "$log_dir"
cd "$ProjDir"
qsub -wd $ProjDir -o :${log_dir}/ -e :${log_dir}/ -N "$script_name" "$this_script"
