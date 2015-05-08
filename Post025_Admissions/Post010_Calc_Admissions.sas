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
		time_period
		,inc_start format = 12.
		,inc_end format = 12.
		,paid_thru format = 12.
	into :time_period separated by "~"
		,:inc_start separated by "~"
		,:inc_end separated by "~"
		,:paid_thru separated by "~"
	from post008.Time_windows
	;
quit;

%put time_period = &time_period.;
%put inc_start = &inc_start.;
%put inc_end = &inc_end.;
%put paid_thru = &paid_thru.;


/*Used Ongoing_Util_Basis=Discharge and Force_Util=No to match the cost model program*/
/*Import inpatient claims excluding SNF for the "Current" time period*/
%agg_claims(
		IncStart=&inc_start.
		,IncEnd=&inc_end.
		,PaidThru=&paid_thru.
		,Med_Rx=Med
		,Ongoing_Util_Basis=Discharge
		,Force_Util=N
		,Dimensions=prm_line~caseadmitid~member_id
		,Time_Slice=&time_period.
		,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)



proc sort data=agg_claims_med out=claims_sort;
	by member_id  time_period date_case_latest date_case_earliest;
run;


/*Determine if there are readmissions within 30 days*/
data claims_w_readmit (drop=prev_discharge prev_time_period);
	set claims_sort;
	by member_id;

	format	
			prev_discharge yymmddd10.
			prev_time_period $32.
			Readmit $1.
			;

	retain prev_discharge prev_time_period;
		if first.member_id then do;
				prev_discharge = date_case_latest;
				prev_time_period = time_slice;
		end;
		if date_case_earliest-prev_discharge le 30 
			and date_case_earliest-prev_discharge gt 0
			and prev_time_period = time_slice then do;
			Readmit = 'Y';
			prev_discharge = date_case_latest;
		end;
		else Readmit = 'N';
run;

/*Limit acute IP stays by removing the following prm_lines:
	I11b--Medical - Rehabilitation
	I13b--Psychiatric - Residential
	I14b--Alcohol and Drug Abuse - Residential
*/
proc sql;
	create table claims_elig as
	select
		a.time_slice
		,a.member_id
		,a.discharges
		,a.prm_costs
		,(case when a.prm_line not in ('I11b', 'I13b', 'I14b') then 'Y' else 'N' end) as Acute_Discharge
		,(case when a.prm_line in ('I11a', 'I11b') then 'Med' 
			  when a.prm_line = 'I12' then 'Surg' else 'N/A' end) as Med_Surg
		,(case when a.prm_util = 1 then 'Y' else 'N' end) as One_day_stay
		,a.readmit
	from claims_w_readmit as a
	inner join post008.members as b on
		a.member_id = b.member_id and a.time_slice = b.time_period
	;
quit;
		
%run_hcc_wrap_prm(&inc_start_current.
		,&inc_end_current.
		,&paid_thru_current.
		,current
		,post008
		)

/*Limit HCC to the members in the member roster*/
proc sql;
	create table HCC_Limit as
	select
		a.time_slice
		,a.hicno
		,a.score_community
	from post008.HCC_results as a
	inner join post008.members as b on 
		a.hicno = b.member_id and a.time_slice = b.time_period
	;
quit;
