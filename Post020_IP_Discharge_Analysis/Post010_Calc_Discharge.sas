/*
### CODE OWNERS: David Pierce, Anna Chen

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


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
libname post008 "&post008." access = readonly;
libname post020 "&post020.";


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
	,Dimensions=member_ID~DRG~DischargeStatus
	,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
	
);

*Calculate the total admits by each time_slice;
proc sql;
	create table obssum_by_period as
	select time_slice, sum(admits) as obssum
	from Agg_claims_med
	group by time_slice
;
quit;

/*Add in discharge status description;*/
data disch_xwalk;
	infile "%GetParentFolder(0)Discharge_status_xwalk.csv"
		lrecl=2048
		firstobs=2
		missover
		dsd
		delimiter=','
		;
	input
		disch_code :$2.
		disch_desc :$32.
		;
run;

proc sql;
	create table Agg_Claims_med_w_desc as
	select
		claims.*
		,coalesce(xwalk.disch_desc,'Other') as Discharge_Desc format $256. 
	from Agg_claims_med as claims
	left join disch_xwalk as xwalk on
		claims.DischargeStatus = xwalk.disch_code
	;
quit;

/*Create a summary by Discharge/DRG combo for NYH to use to normalize, then get a discharge only summary
  first we are going to stage up the discharge data by time period and limit to only members in our member table then summarize*/
proc sql;
	create table discharge_pre as
		select
			src.time_slice as time_period
			,DRG
			,src.DischargeStatus
			,Discharge_Desc
			,src.Admits
			,coalesce((src.admits/obs.obssum),0) as Admits_pct
			,src.PRM_Costs
			,"&name_client." as name_client

		 from Agg_Claims_med_w_desc as src
		 
		 inner join Post008.Members as memb on
		 		src.member_ID = memb.member_ID
			and src.time_slice = memb.time_period

		 left join Obssum_by_period as obs 
		 	on src.time_slice = obs.time_slice
;
quit;

proc sql;
	create table post020.DRG_Discharge_totals_1 as
		select
			"Discharge" as Metric
			,src.time_period
			,src.DRG
			,src.Discharge_Desc
			,SUM(src.Admits) as Admits
			,SUM(src.Admits_pct) as Admits_pct
			,SUM(src.PRM_Costs) as PRM_Costs
			,src.name_client
		from discharge_pre as src
		group by src.time_period,src.DRG,src.Discharge_Desc,src.name_client
;
quit;

proc sql;
	create table post020.Discharge_totals_1 as
		select
			"Discharge" as Metric
			,src.time_period
			,src.Discharge_Desc
			,SUM(src.Admits) as Admits
			,SUM(src.Admits_pct) as Admits_pct
			,SUM(src.PRM_Costs) as PRM_Costs
			,src.name_client
		from discharge_pre as src
		group by src.time_period,src.Discharge_Desc,src.name_client
;
quit;

%LabelDataSet(post020.DRG_Discharge_totals)
%LabelDataSet(post020.Discharge_totals)

%put System Return Code = &syscc.;


