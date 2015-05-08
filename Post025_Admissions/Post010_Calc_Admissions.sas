/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Use the PRM outputs to create the Admissiion/Readmission report for NYP.

### DEVELOPER NOTES:
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";
%include "&M008_Cde.Func04_run_hcc_wrap_prm.sas";

/*Libnames*/
libname post008 "&post008.";


proc sql noprint;
	select 
		inc_start format = 12.
		,inc_end format = 12.
		,paid_thru format = 12.
	into time_period separated by "~"
		,:inc_start separated by "~"
		,:inc_end separated by "~"
		,:paid_thru separated by "~"
	from post008.Time_windows
	;
quit;

%put time_period = &time_period.;
%put inc_start = &inc_start_current.;
%put inc_end = &inc_end_current.;
%put paid_thru = &paid_thru_current.;


/*Used Ongoing_Util_Basis=Discharge and Force_Util=No to match the cost model program*/
/*Import inpatient claims excluding SNF for the "Current" time period*/
%agg_claims(
		IncStart=&inc_start_current.
		,IncEnd=&inc_end_current.
		,PaidThru=&paid_thru_current.
		,Med_Rx=Med
		,Ongoing_Util_Basis=Discharge
		,Force_Util=N
		,Dimensions=prm_line~caseadmitid~memberid
		,Time_Slice=Current
		,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)

/*Extract medical member months*/
proc sql noprint;
	select memmos_medical
	into :member_months_current
	from agg_memmos_current
;
quit;
%put memmos = &member_months_current.;

%run_hcc_wrap_prm(&inc_start_current.
		,&inc_end_current.
		,&paid_thru_current.
		,current
		,post008
		)

/*Determine average HCC Risk Score*/
proc sql noprint;
	select avg(score_community)
	into :HCC_Score
	from post008.HCC_results
	;
quit;
%put HCC Risk Score = &HCC_Score.;


/*Limit to acute IP stays by removing the following prm_lines:
	I11b--Medical - Rehabilitation
	I13b--Psychiatric - Residential
	I14b--Alcohol and Drug Abuse - Residential
*/
proc sql noprint;
	select sum(discharges)
	into :acute_admits
	from agg_claims_med_current
	where prm_line not in ('I11b', 'I13b', 'I14b')
	;
quit;
%put Acute Admits = &acute_admits.;

/*Limit to Medical Admissions I11a and I11b*/
proc sql noprint;
	select sum(discharges)
	into :medical_admits
	from agg_claims_med_current
	where prm_line in ('I11a', 'I11b')
	;
quit;
%put Medical Admits = &medical_admits.;

/*Limit to Surgical Admissions I12*/
proc sql noprint;
	select sum(discharges)
	into :surgical_admits
	from agg_claims_med_current
	where prm_line = 'I12'
	;
quit;
%put Surgical Admits = &surgical_admits.;

/*Count total admits*/
proc sql noprint;
	select sum(discharges)
	into :total_admits
	from agg_claims_med_current
	;
quit;
%put Total Admits = &total_admits.;

/*Count 1 day LOS*/
proc sql noprint;
	select count(CaseAdmitID)
	into :LOS_1_Day
	from agg_claims_med_current
	where PRM_Util = 1 and discharges gt 0
	;
run;
%put LOS 1 Day = &LOS_1_Day.;
