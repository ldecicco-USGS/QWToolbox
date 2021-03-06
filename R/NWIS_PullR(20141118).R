DSN <- "NWISCO"
env.db <- "01"
qa.db <- "02"
STAIDS <- c("391454106224201",
            "391500106224901",
           "391501106224901",
            "391504106225200",
            "391504106225201")
dl.parms <- read.csv("Data/pcodes.csv", header=F,colClasses = "character")
parm.group.check <- TRUE
dl.parms <- "IMM"



NWISPullR <- function(DSN,env.db = "01",qa.db = "02",STAIDS,dl.parms,parm.group.check = FALSE,begin.date,end.date)
{
  #Change to a list that SQL can understand. SQL requires a parenthesized list of expressions, so must look like c('05325000', '05330000') for example
  STAID.list <- paste("'", STAIDS, "'", sep="", collapse=",")
  


  #############################################################################
  Chan1 <- odbcConnect(DSN)###Start of ODBC connection
  #############################################################################
  
  ##################
  ###Env Database###
  ##################
  # First get the site info--need column SITE_ID
  Query <- paste("select * from ", DSN, ".SITEFILE_",env.db," where site_no IN (", STAID.list, ")", sep="")
  SiteFile <- sqlQuery(Chan1, Query, as.is=T)
  
  #get the record numbers
  Query <- paste("select * from ", DSN, ".QW_SAMPLE_",env.db," where site_no IN (", STAID.list, ")", sep="")
  Samples <- sqlQuery(Chan1, Query, as.is=T)
  
  #Subset records to date range, times are in GMT, which is the universal NWIS time so that you can have a consistant date-range accross timezones.
  #Time is corrected to local sample timezone before plotting
  Samples$SAMPLE_START_DT <- as.POSIXct(Samples$SAMPLE_START_DT, tz="GMT")
  if(!is.na(begin.date) && !is.na(end.date)) {
  Samples <- subset(Samples, SAMPLE_START_DT >= begin.date & SAMPLE_START_DT <= end.date)
  }else {} 
  #get the QWResult file using the record numbers
  records.list <- paste("'", Samples$RECORD_NO, "'", sep="", collapse=",")
  Query <- paste("select * from ", DSN, ".QW_RESULT_",env.db," where record_no IN (", records.list, ")", sep="")
  Results <- sqlQuery(Chan1, Query, as.is=T)
  Results$Val_qual <- paste(Results$RESULT_VA,Results$REMARK_CD, sep = " ")
  Results$Val_qual <- gsub("NA","",Results$Val_qual)
  
  #Get list of parm names
  parms.list <- paste("'", unique(Results$PARM_CD), "'", sep="", collapse=",")
  
  Query <- paste("select * from ", DSN, ".PARM where PARM_CD IN (", parms.list, ")", sep="")
  parms <- sqlQuery(Chan1, Query, as.is=T)
  parms <- parms[c("PARM_CD","PARM_SEQ_GRP_CD","PARM_DS")]
  
  #station names and dates
  name_num <- SiteFile[c("SITE_NO","STATION_NM")]
  Sample_meta <- join(Samples, name_num,by="SITE_NO")
  Sample_meta <- Sample_meta[c("SITE_NO","STATION_NM","SAMPLE_START_DT","SAMPLE_START_TZ_CD","SAMPLE_START_LOCAL_TM_FG","SAMPLE_END_DT","MEDIUM_CD","RECORD_NO","LAB_NO")]
  
  
  ##Format times into GMT and correct of daylight savings offset according to location
  ##Weather or not to apply daylight savings is in the std.time.code column, which is from the SAMPLE_START_LOCAL_TM_FG NWIS parameter
  ##e.g. in Colorado, SAMPLE_START_LOCAL_TM_FG = Y, timezone = MDT, SAMPLE_START_LOCAL_TM_FG = N, timezone = MST
  Sample_meta$SAMPLE_START_DT <- as.POSIXct(Sample_meta$SAMPLE_START_DT, tz="GMT")
  Sample_meta$offset <- ifelse (Sample_meta$SAMPLE_START_LOCAL_TM_FG == "Y", 60*60,0)
  Sample_meta$start.date.offset <- Sample_meta$SAMPLE_START_DT + Sample_meta$offset
  ###Format times from GMT to appropriate time zone
  ###Using a loop because I could not figure out how to vectorize it, perhaps "mapply" would work, but don't know
  for ( i in 1:nrow(Sample_meta))
  {
    ###Converts to time zone
    Sample_meta$start.date.adj[i] <- format(Sample_meta$start.date.offset[i],"%Y-%m-%d %H:%M:%S", tz=as.character(Sample_meta$SAMPLE_START_TZ_CD[i]))
  }
  
  Sample_meta$SAMPLE_START_DT <- Sample_meta$start.date.adj 
  Sample_meta$start.date.adj <- NULL
  Sample_meta$offset <- NULL
  Sample_meta$start.date.offset <- NULL
  Sample_meta$SAMPLE_START_TZ_CD <- NULL
  Sample_meta$SAMPLE_START_LOCAL_TM_FG <- NULL
  

  #join tables so parm names are together
  Results<- join(Results,parms,by="PARM_CD")
  
  #Subset results to selected parmeters
  if (parm.group.check == TRUE) 
  {
    if(dl.parms != "All")
    {
      Results <- subset(Results, PARM_SEQ_GRP_CD == dl.parms)
    } else{ Results<- join(Results,parms,by="PARM_CD")} 
  } else {Results <- subset(Results, PARM_CD %in% dl.parms)}
  

  
  #Make dataframe as record number and pcode. MUST HAVE ALL UNIQUE PCODE NAMES
  DataTable1 <- dcast(Results, RECORD_NO ~ PARM_DS ,value.var = c("Val_qual"))
  
  #fill in record number meta data (statoin ID, name, date, time)
  DataTable1 <- join(DataTable1,Sample_meta, by="RECORD_NO")
  
  #reorder columns so meta data is at front
  parmcols <- seq(from =1, to =ncol(DataTable1)-5 )
  metacols <- seq(from = ncol(DataTable1)-4, to =ncol(DataTable1))
  DataTable1 <- DataTable1[c(metacols,parmcols)]
  PlotTable1 <- join(Results,Sample_meta,by="RECORD_NO")
  
  ##################
  ###QA Database####
  ##################
  # First get the site info--need column SITE_ID
  Query <- paste("select * from ", DSN, ".SITEFILE_",qa.db," where site_no IN (", STAID.list, ")", sep="")
  SiteFile <- sqlQuery(Chan1, Query, as.is=T)
  
  #get the record numbers
  Query <- paste("select * from ", DSN, ".QW_SAMPLE_",qa.db," where site_no IN (", STAID.list, ")", sep="")
  Samples <- sqlQuery(Chan1, Query, as.is=T)
  
  #Subset records to date range, times are in GMT, which is the universal NWIS time so that you can have a consistant date-range accross timezones.
  #Time is corrected to local sample timezone before plotting
  Samples$SAMPLE_START_DT <- as.POSIXct(Samples$SAMPLE_START_DT, tz="GMT")
  if(!is.na(begin.date) && !is.na(end.date)) {
    Samples <- subset(Samples, SAMPLE_START_DT >= begin.date & SAMPLE_START_DT <= end.date)
  }else {} 
  
  #get the QWResult file using the record numbers
  records.list <- paste("'", Samples$RECORD_NO, "'", sep="", collapse=",")
  Query <- paste("select * from ", DSN, ".QW_RESULT_",qa.db," where record_no IN (", records.list, ")", sep="")
  Results <- sqlQuery(Chan1, Query, as.is=T)
  Results$Val_qual <- paste(Results$RESULT_VA,Results$REMARK_CD, sep = " ")
  Results$Val_qual <- gsub("NA","",Results$Val_qual)
  
  #Get list of parm names
  parms.list <- paste("'", unique(Results$PARM_CD), "'", sep="", collapse=",")
  
  Query <- paste("select * from ", DSN, ".PARM where PARM_CD IN (", parms.list, ")", sep="")
  parms <- sqlQuery(Chan1, Query, as.is=T)
  parms <- parms[c("PARM_CD","PARM_SEQ_GRP_CD","PARM_DS")]
  
  #############################################################################
  odbcClose(Chan1)###End of ODBC connection
  #############################################################################
  
  #station names and dates
  name_num <- SiteFile[c("SITE_NO","STATION_NM")]
  Sample_meta <- join(Samples, name_num,by="SITE_NO")
  Sample_meta <- Sample_meta[c("SITE_NO","STATION_NM","SAMPLE_START_DT","SAMPLE_START_TZ_CD","SAMPLE_START_LOCAL_TM_FG","SAMPLE_END_DT","MEDIUM_CD","RECORD_NO","LAB_NO")]
  
  
  ##Format times into GMT and correct of daylight savings offset according to location
  ##Weather or not to apply daylight savings is in the std.time.code column, which is from the SAMPLE_START_LOCAL_TM_FG NWIS parameter
  ##e.g. in Colorado, SAMPLE_START_LOCAL_TM_FG = Y, timezone = MDT, SAMPLE_START_LOCAL_TM_FG = N, timezone = MST
  Sample_meta$SAMPLE_START_DT <- as.POSIXct(Sample_meta$SAMPLE_START_DT, tz="GMT")
  Sample_meta$offset <- ifelse (Sample_meta$SAMPLE_START_LOCAL_TM_FG == "Y", 60*60,0)
  Sample_meta$start.date.offset <- Sample_meta$SAMPLE_START_DT + Sample_meta$offset
  ###Format times from GMT to appropriate time zone
  ###Using a loop because I could not figure out how to vectorize it, perhaps "mapply" would work, but don't know
  for ( i in 1:nrow(Sample_meta))
  {
    ###Converts to time zone
    Sample_meta$start.date.adj[i] <- format(Sample_meta$start.date.offset[i],"%Y-%m-%d %H:%M:%S", tz=as.character(Sample_meta$SAMPLE_START_TZ_CD[i]))
  }
  
  Sample_meta$SAMPLE_START_DT <- Sample_meta$start.date.adj 
  Sample_meta$start.date.adj <- NULL
  Sample_meta$offset <- NULL
  Sample_meta$start.date.offset <- NULL
  Sample_meta$SAMPLE_START_TZ_CD <- NULL
  Sample_meta$SAMPLE_START_LOCAL_TM_FG <- NULL
  
  
  #join tables so parm names are together
  Results<- join(Results,parms,by="PARM_CD")
  
  #Subset results to selected parmeters
  if (parm.group.check == TRUE) 
  {
    if(dl.parms != "All")
    {
      Results <- subset(Results, PARM_SEQ_GRP_CD == dl.parms)
    } else{Results<- join(Results,parms,by="PARM_CD")} 
  } else {Results <- subset(Results, PARM_CD %in% dl.parms)}
 
  #Make dataframe as record number and pcode. MUST HAVE ALL UNIQUE PCODE NAMES
  DataTable2 <- dcast(Results, RECORD_NO ~ PARM_DS,value.var = "Val_qual")
  
  #fill in record number meta data (statoin ID, name, date, time)
  DataTable2 <- join(DataTable2,Sample_meta, by="RECORD_NO")
  
  #reorder columns so meta data is at front
  parmcols <- seq(from =1, to =ncol(DataTable2)-5 )
  metacols <- seq(from = ncol(DataTable2)-4, to =ncol(DataTable2))
  DataTable2 <- DataTable2[c(metacols,parmcols)]
  PlotTable2 <- join(Results,Sample_meta,by="RECORD_NO")
  
  DataTable <- rbind.fill(DataTable1,DataTable2)
  PlotTable <- rbind.fill(PlotTable1,PlotTable2)
  PlotTable$REMARK_CD <- gsub("NA","",PlotTable$REMARK_CD)
  PlotTable$SAMPLE_START_DT <- as.POSIXct(PlotTable$SAMPLE_START_DT)
  PlotTable$REMARK_CD[is.na(PlotTable$REMARK_CD)] <- "Sample"
  PlotTable$REMARK_CD <- as.factor(PlotTable$REMARK_CD)
  PlotTable$REMARK_CD = factor(PlotTable$REMARK_CD,levels(PlotTable$REMARK_CD)[c(4,1:3)])
  PlotTable$RESULT_VA <- as.numeric(PlotTable$RESULT_VA)
  ###Get month for seasonal plots and reorder factor levels to match water-year order
  PlotTable$SAMPLE_MONTH <-  factor(format(PlotTable$SAMPLE_START_DT,"%b"),levels=c("Oct","Nov","Dec","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep"))

  # Close the connection

  
  
  return(list(DataTable=DataTable,PlotTable=PlotTable))
  
}
