#!/bin/bash
#SBATCH --account=rrg-ziels
#SBATCH --array=1-4
#SBATCH --cpus-per-task=12
#SBATCH --mem-per-cpu=60G
#SBATCH --time=22:0:0
#SBATCH --job-name=unicycler-hybrid-assembly
#SBATCH --output=%x.out
#SBATCH --mail-user=eamcdani@mail.ubc.ca
#SBATCH --mail-type=ALL

# mapping to Nanopore and Illumina genome assemblies for select genome bins, feeding the sets of reads to Unicycler for a hybrid binning approach of the two
# array job based on directory names

# map the NP reads with minimap2 
# map the Illumina reads from Sept 2020 sample with bowtie2
# bamtofastq to feed reads to Unicycler

#paths
project_path="/project/6049207/AD_metagenome-Elizabeth"
dirs_path="${project_path}/re_binning/np_binning_v2_poly/unicycler_hybrid"
r1_read_path="${project_path}/00_illumina_for_polishing/illumina_qced/R2Sept2020_R1.qced.fastq"
r2_read_path="${project_path}/00_illumina_for_polishing/illumina_qced/R2Sept2020_R2.qced.fastq"
np_read_path="${project_path}/03_porechop_trimmed/AD_SIP_trimmed_combined.fastq"

# assembly directory name based from the array job
dir_name=$(sed -n "${SLURM_ARRAY_TASK_ID}p" unicycler_dir_files.txt | awk -F "\t" '{print $1}')

# long read assembly 
np_assembly=$(sed -n "${SLURM_ARRAY_TASK_ID}p" unicycler_dir_files.txt | awk -F "\t" '{print $2}')

# short read assembly
ilm_assembly=$(sed -n "${SLURM_ARRAY_TASK_ID}p" unicycler_dir_files.txt | awk -F "\t" '{print $3}')

# modules
# bowtie and minimap2 mapping, samtools, unicycler Singularity image
module load StdEnv/2020 gcc/9.3.0 bowtie2 samtools minimap2 bedtools singularity

# cd into the directory 
cd ${dirs_path}/${dir_name}
mkdir bt2

# make bowtie2 index of the short read assembly
bowtie2-build ${ilm_assembly} bt2/ilm_assembly

# map short reads to the short read assembly
bowtie2 -x bt2/ilm_assembly -1 ${r1_read_path} -2 ${r2_read_path} -q --very-sensitive -p 10 -S ilm_assembly_vs_ilm_reads.sam

# map long reads to the long read assembly
minimap2 -t 10 -x map-ont -a ${np_assembly} ${np_read_path} > np_assembly_vs_long_reads.sam 

# sort and index all the SAM > BAM files 
for file in *.sam; do
	name=$(basename $file .sam);
	samtools view -@ 10 -S -b $file > ${name}.bam;
	samtools sort -@ 10 ${name}.bam -o ${name}.sorted.bam;
	samtools index ${name}.sorted.bam;
done 

# convert every sorted BAM file to a FASTQ file of reads 
for file in *_vs_ilm_reads.sorted.bam; do
	name=$(basename $file .sorted.bam);
	samtools fastq $file -1 ${name}_1.fastq -2 ${name}_2.fastq;
done

for file in *_vs_long_reads.sorted.bam; do
	name=$(basename $file .sorted.bam);
	bedtools bamtofastq -i $file -fq ${name}.fastq; 
done # has to be done with bamtofastq because samtools fastq command expecting paired end reads and did weird things

# unicycler command 
singularity exec -B /home -B /project -B /scratch -B /localscratch ${project_path}/singularity_images/unicycler_v0.4.9.sif unicycler -1 ilm_assembly_vs_ilm_reads_1.fastq -2 ilm_assembly_vs_ilm_reads_2.fastq -l np_assembly_vs_long_reads.fastq -o ${dir_name}_unicycler