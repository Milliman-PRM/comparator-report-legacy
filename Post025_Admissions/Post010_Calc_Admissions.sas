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
	into :inc_start_current
		,:inc_end_current
		,:paid_thru_current
	from post008.Time_windows
	where time_period = "Current"
	;
quit;

%put inc_start_current = &inc_start_current.;
%put inc_end_current = &inc_end_current.;
%put paid_thru_current = &paid_thru_current.;


/*Used Ongoing_Util_Basis=Discharge and Force_Util=No to match the cost model program*/
/*Import inpatient claims excluding SNF for the "Current" time period*/
%agg_claims(
		IncStart=&inc_start_current.
		,IncEnd=&inc_end_current.
		,PaidThru=&paid_thru_current.
		,Med_Rx=Med
		,Ongoing_Util_Basis=Discharge
		,Force_Util=N
		,Dimensions=prm_line~caseadmitid
		,Time_Slice=Current
		,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)


/*Limit to acute IP stays by removing the following prm_lines:
	I11b--Medical - Rehabilitation
	I13b--Psychiatric - Residential
	I14b--Alcohol and Drug Abuse - Residential
*/

%run_hcc_wrap_prm(&inc_start_current.
		,&inc_end_current.
		,&paid_thru_current.
		,current
		,post008
		)

/*Determine member months for per 1000 calcs*/





/*Limit to Acute Inpatient Admissions*/
proc summary nway missing data = agg_claims_med_current;
var discharges;
where prm_line not in ('I11b', 'I13b', 'I14b');
output out=acute_ip_admits (drop = _:)sum=total_admits;
run;

/*Limit to Medical Admissions I11a and I11b*/
proc summary nway missing data = agg_claims_med_current;
var discharges;
where prm_line in ('I11a', 'I11b');
output out=medical_ip_admits (drop = _:)sum=total_admits;
run;

/*Limit to Surgical Admissions I12*/
proc summary nway missing data = agg_claims_med_current;
var discharges;
where prm_line = 'I12';
output out=surgical_ip_admits (drop = _:)sum=total_admits;
run;

