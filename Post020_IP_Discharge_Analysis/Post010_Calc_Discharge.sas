/*
### CODE OWNERS: David Pierce, 

### OBJECTIVE:
	Find the distribution of paid percent, number of admits percent, and number of days admitted percent to 
	hospital groups for each discharge code and provider name.

### DEVELOPER NOTES:
  1) Only use beneficiaries that didn't opt out, weren't excluded, and didn't opt back in.
  2) Create "categ" for use when summarizing paid amount, number of admits, and number of days admitted by discharge code and ACO.

*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

libname post008 "&post008.";
libname post020 "&post020.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/*Pull out the start/end dates from the time windows dataset*/
proc sql noprint;
	select
		time_period
		,inc_start format = 12.
		,inc_end format = 12.
		,paid_thru format = 12.
	into  :time_period separated by "~"
		 ,:inc_start separated by "~"
		 ,:inc_end separated by "~"
		 ,:paid_thru separated by "~"
	from post008.Time_Windows
	;
quit;
%put time_period = &time_period.;
%put inc_start_prior = &inc_start.;
%put inc_end_prior = &inc_end.;
%put paid_thru_prior = &paid_thru.;

*Create the current and prior data seta with only the metrics that we need and with only eligible members using the function call;
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru = &paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Dimensions=member_ID~DischargeStatus
	,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
	
);

*Calculate the total admits by period;
proc sql noprint;
	select sum(admits)
	into :curr_obssum
	from Agg_claims_med
	where upcase(time_slice) = "CURRENT"
;
quit;
%put sum = &curr_obssum;

proc sql noprint;
	select sum(admits)
	into :prior_obssum
	from Agg_claims_med
	where upcase(time_slice) = "PRIOR"
;
quit;
%put sum = &prior_obssum;

proc sql;
	create table post020.Discharge_totals as
		select
			"Discharge" as Metric
			,nest.time_slice as time_period
			,nest.Discharge_Desc
			,SUM(Admits) as Admits
			,SUM(Admits_pct) as Admits_pct
			,SUM(PRM_Costs) as PRM_Costs
			,name_client
		from (
			select
				src.time_slice
				,src.DischargeStatus
				,Case when src.DischargeStatus = "01" then "Discharged to Home"
			  		  when src.DischargeStatus = "62" then "Discharged to IRF"
			  		  when src.DischargeStatus = "03" then "Discharged to SNF"
			  		  when src.DischargeStatus = "06" then "Discharged to Home Health Care"
					  when src.DischargeStatus = "20" then "Died"
			  		  else "Other"
		 		 End as Discharge_Desc
				,src.Admits
				,Case when upcase(src.time_slice) = "CURRENT" then (src.admits /&curr_obssum.)
					  when upcase(src.time_slice) = "PRIOR" then (src.admits/&prior_obssum.)
					  else 0
				 END as Admits_pct
				,src.PRM_Costs
				,"&name_client." as name_client

			 from Agg_claims_med as src

			  ) as NEST

		group by nest.time_slice,nest.Discharge_Desc,nest.name_client
;
quit;

%LabelDataSet(post020.Discharge_totals)

%put System Return Code = &syscc.;


