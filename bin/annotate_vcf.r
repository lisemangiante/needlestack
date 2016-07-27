#! /usr/bin/env Rscript

args <- commandArgs(TRUE)
parseArgs <- function(x) strsplit(sub("^--", "", x), "=")
argsL <- as.list(as.character(as.data.frame(do.call("rbind", parseArgs(args)))$V2))
names(argsL) <- as.data.frame(do.call("rbind", parseArgs(args)))$V1
args <- argsL;rm(argsL)

if(is.null(args$input_vcf))            {stop("no input VCF file")} else {input_vcf = args$input_vcf}
if(is.null(args$out_vcf))              {args$out_vcf = out_vcf = paste(gsub(".vcf.bgz","",input_vcf),"_annotated_needlestack.vcf",sep="")} else {out_vcf=args$out_vcf}
if(nchar(args$out_vcf)==0)             {out_vcf = paste(gsub(".vcf.bgz","",input_vcf),"_annotated_needlestack.vcf",sep="")}
if(is.null(args$chunk_size))           {chunk_size = 1000} else {chunk_size = as.numeric(args$chunk_size)}
if(is.null(args$do_plots))             {do_plots = TRUE} else {do_plots = as.logical(args$do_plots)}
if(is.null(args$plot_labels))          {plot_labels = TRUE} else {plot_labels = as.logical(args$plot_labels)}
if(is.null(args$add_contours))         {add_contours = TRUE} else {add_contours = as.logical(args$add_contours)}
if(is.null(args$min_coverage))         {min_coverage = 50} else {min_coverage = as.numeric(args$min_coverage)}
if(is.null(args$min_reads))            {min_reads = 5} else {min_reads = as.numeric(args$min_reads)}
if(is.null(args$GQ_threshold))         {GQ_threshold=50} else {GQ_threshold = as.numeric(args$GQ_threshold)}
if(is.null(args$SB_threshold))         {SB_threshold=100} else {SB_threshold = as.numeric(args$SB_threshold)}

source(paste(args$source_path,"glm_rob_nb.r",sep=""))
source(paste(args$source_path,"plot_rob_nb.r",sep=""))
library(VariantAnnotation)

#initiate the first chunk
vcf <- open(VcfFile(input_vcf,  yieldSize=chunk_size))
vcf_chunk = readVcf(vcf, "hg19")

#and continue
while(dim(vcf_chunk)[1] != 0) {
  # coverage (matrix of integers)
  DP_matrix = geno(vcf_chunk,"DP")
  # AO counts (matrix of lists of integers)
  AD_matrix = geno(vcf_chunk,"AD")

  #compute regressions and qvals,err,sig
  reg_list = lapply(1:dim(vcf_chunk)[1], function(var_line) { #for each line of the chunk return a list of reg for each AD
    lapply(2:max(lengths(AD_matrix[var_line,])), function(AD_index) { #for each alternative
      DP=DP_matrix[var_line,]
      AD_matrix[var_line, which(is.na(AD_matrix[var_line,]))] = lapply(AD_matrix[var_line, which(is.na(AD_matrix[var_line,]))], function(x) x=as.vector(rep(0,max(lengths(AD_matrix[var_line,])))))
      AO=unlist(lapply(AD_matrix[var_line,],"[[",AD_index)) #AD_matrix[var_line,] is a list of AD for each sample, here return list of ADs(i) for alt i
      reg_res=glmrob.nb(x=DP,y=AO,min_coverage=min_coverage,min_reads=min_reads)
      if (do_plots) {
        chr=as.character(seqnames(rowRanges(vcf_chunk,"seqnames"))[var_line])
        loc=start(ranges(rowRanges(vcf_chunk,"seqnames"))[var_line])
        ref=as.character(ref(vcf_chunk)[[var_line]])
        alt=alt(vcf_chunk)[[var_line]]
        sbs=rep(NA,dim(vcf_chunk)[2])
        pdf(paste(chr,"_",loc,"_",loc,"_",ref,"_",alt,".pdf",sep=""),7,6)
        plot_rob_nb(reg_res, 10^-(GQ_threshold/10), plot_title=paste(chr, " ", loc," (",ref," -> ",alt,")",sep=""), sbs=sbs, SB_threshold=SB_threshold,plot_labels=T,add_contours=T,names=samples(header(vcf_chunk)))
        dev.off()
      }
      reg_res
    })
  })
  qvals = lapply(reg_list, function(regs) {
    lapply(regs, function(reg) (unlist(reg["GQ"])+0)) #here add +0 to avoid sprintf wrinting -0
  })
  err = lapply(reg_list, function(regs) {
    lapply(regs, function(reg) unlist(reg$coef["slope"]))
  })
  sig = lapply(reg_list, function(regs) {
    lapply(regs, function(reg) unlist(reg$coef["sigma"]))
  })

  #annotate the header of the chunk
  info(header(vcf_chunk))["ERR",]=list(1,"Integer","Error rate estimated by needlestack")
  info(header(vcf_chunk))["SIG",]=list(1,"Integer","Dispertion parameter estimated by needlestack")
  geno(header(vcf_chunk))["QVAL",]=list(1,"Integer","Phred q-values computed by needlestack")

  #annotate the chunk with computed values
  info(vcf_chunk)$ERR = matrix(data = unlist(lapply(err, function(e) as.list(data.frame(mapply(c,e)))),recursive = FALSE),
                               nrow = dim(vcf_chunk)[1],
                               byrow = TRUE)
  info(vcf_chunk)$SIG = matrix(data = unlist(lapply(sig, function(s) as.list(data.frame(mapply(c,s)))),recursive = FALSE),
                               nrow = dim(vcf_chunk)[1],
                               byrow = TRUE)
  geno(vcf_chunk)$QVAL = matrix(data = unlist(lapply(qvals, function(q) as.list(data.frame(t(mapply(c,q))))),recursive = FALSE),
                                nrow = dim(vcf_chunk)[1],
                                byrow = TRUE)

  #write out the annotated VCF
  con = file(out_vcf, open = "a")
  writeVcf(vcf_chunk, con)
  vcf_chunk = readVcf(vcf, "hg19")
  close(con)
}
