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
%include "&M002_cde.supp01_validation_functions.sas";

/*Libnames*/
libname post008 "&post008.";
libname post025 "&post025.";

/*Create macro variables to be used in developing the metrics*/
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
		,Dimensions=prm_line~caseadmitid~member_id~dischargestatus~providerID~prm_readmit_all_cause_yn~prm_ahrq_pqi
		,Time_Slice=&time_period.
		,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
		,Where_Elig=
		,Date_DateTime=
		,Suffix_Output=
		)


/*Determine memmos and risk score for use in calculating the metrics*/

proc sql;
	create table mem_w_rskscr
	select
		memmos.*
		,members.riskscr_1
	from agg_memmos as memmos
	left join post008.members as members on
		memmos.member_id = members.member_id
	;
quit;

/*Determine the member months per time period*/
proc sql noprint;
	select
		sum(case when time_slice = "Current" then memmos_medical else 0 end)
		,sum(case when time_slice = "Prior" then memmos_medical else 0 end)
	into :memmos_current
		,:memmos_prior
	from mem_w_rskscr
	;
quit;
%put current_memmos = &memmos_current.;
%put prior_memmos = &memmos_prior.;

/*Determine the average risk score by time period*/
proc sql;
	select
		sum(case when time_slice = "Current" then memmos_medical*riskscr_1 else 0 end)/&memmos_current.
		,sum(case when time_slcie = "Prior" then memmos_medical*riskscr_1 else 0 end)/&memmos_prior.
	into :rskscr_current
		,:rskscr_prior
	from mem_w_rskscr
	;
quit;
%put risk_score_current = &rskscr_current.;
%put risk_score_prior = &rskscr_prior.;


/*Limit acute IP stays by removing the following prm_lines:
	I11b--Medical - Rehabilitation
	I13a--Psychiatric - Hospital
	I13b--Psychiatric - Residential
*/
proc sql;
	create table claims_elig as
	select
		"&name_client." as name_client
		,a.time_slice as time_period
		,a.member_id
		,a.providerid as prv_id_inpatient
		,a.discharges
		,a.dischargestatus as discharge_status_code
		,a.prm_util as days
		,a.prm_util as los_inpatient
		,a.prm_costs as costs
		,a.prm_drg as drg_inpatient
		,a.prm_drgversion as drg_version_inpatient
		,(case when a.prm_line not in ('I11b', 'I13a', 'I13b') then 'Y' else 'N' end) as acute_yn
		,(case when a.prm_line in ('I11a', 'I11b') then 'Medical' 
			  when a.prm_line = 'I12' then 'Surgical' else 'N/A' end) as medical_surgical
		,a.prm_readmit_all_cause_yn as inpatient_readmit_yn
		,(case when a.prm_ahrq_pqi = 'None' then 'N' else 'Y' end) as inpatient_pqi_yn
		,'N' as preference_sensitive_yn
	from agg_claims_med as a
	inner join post008.members as b on
		a.member_id = b.member_id and a.time_slice = b.time_period
	;
quit;

/*Add in discharge status description*/
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
	create table claims_w_desc as
	select
		a.*
		,coalesce(b.disch_desc,'Other') as discharge_status_desc
	from claims_elig as a
	left join disch_xwalk as b on
		a.discharge_status_code = b.disch_code
	;
quit;

/*Aggreate the table to the datamart format*/
proc summary nway missing data=claims_w_desc;
class name_client time_period prv_id_inpatient discharge_status_code discharge_status_desc drg_inpatient drg_version_inpatient
	  acute_yn medical_surgical inpatient_pqi_yn preference_sensitive_yn inpatient_readmit_yn los_inpatient;
var discharges days costs;
output out=details_inpatient (drop = _:)sum=cnt_discharges_inpatient sum_days_inpatient sum_costs_inpatient;
run;

%ValidateAgainstTemplate(post025,Comparator_Report)

/*Calculate the requested measures*/
proc sql;
	create table measures as
	select
		time_period
		,sum(case when acute_yn = 'Y' then 1 else 0 end)XXXX as acute_per_1000
		,sum(case when 






		group by time_period



















		

/*
%run_hcc_wrap_prm(&inc_start_current.
		,&inc_end_current.
		,&paid_thru_current.
		,current
		,post008
		)

/*Limit HCC to the members in the member roster
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
*/
