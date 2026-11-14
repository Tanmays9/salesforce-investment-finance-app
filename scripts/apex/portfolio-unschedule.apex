Set<String> names=new Set<String>{'Investments NAV 09 IST','Investments NAV Retry 10 IST','Investments NAV Retry 12 IST'};
for(CronTrigger job:[SELECT Id,CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name IN :names OR CronJobDetail.Name LIKE 'Inv fund metrics continuation %'])System.abortJob(job.Id);
System.debug(LoggingLevel.INFO,'Paused investment refresh schedules and pending fund-metrics continuation jobs for metadata deployment.');
