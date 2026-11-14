if(UserInfo.getTimeZone().getID()!='Asia/Kolkata')throw new InvMath.CalculationException('Run this installer as a user with timezone Asia/Kolkata; no schedules changed.');
Set<String> names=new Set<String>{'Investments NAV 09 IST','Investments NAV Retry 10 IST','Investments NAV Retry 12 IST'};
for(CronTrigger job:[SELECT Id,CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name IN :names])System.abortJob(job.Id);
System.schedule('Investments NAV 09 IST','0 0 9 * * ?',new InvDailyRefresh());
System.schedule('Investments NAV Retry 10 IST','0 0 10 * * ?',new InvDailyRefresh(true));
System.schedule('Investments NAV Retry 12 IST','0 0 12 * * ?',new InvDailyRefresh(true));
System.debug(LoggingLevel.INFO,'Daily NAV refresh and failed-fund retries scheduled in Asia/Kolkata.');
