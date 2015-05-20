/*
### CODE OWNERS: Jason Altieri, Shea Parkes

### OBJECTIVE:
	Identify SNF discharges that were readmitted troublingly quickly.

### DEVELOPER NOTES:
	None
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post040 "&post040.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=providerID~member_ID~prm_line~caseadmitid
	,Force_Util=&post_force_util.
	,where_claims= %str(lowcase(outclaims_prm.prm_line) eqt "i" and lowcase(outclaims_prm.prm_line) not in (&nonacute_ip_prm_line_ignore_snf.))
    );

/*Limit the claims to only those members who are included in our centralized member roster.*/
proc sql noprint;
	create table Agg_med_cases_limited as
		select 
			claims.*
	from agg_claims_med as claims 
	inner join 
		post008.members as mems 
		on claims.time_slice = mems.time_period 
		and claims.member_ID = mems.member_ID
	order by
		claims.time_slice
		,claims.caseadmitid;
quit;


proc sql;
	create table snf_stays as
	select
		time_slice
		,member_id
		,caseadmitid
		,min(date_case_earliest) as date_snf_admit format=YYMMDDd10.
		,max(date_case_latest) as date_snf_discharge format=YYMMDDd10.
	from Agg_med_cases_limited
	where lowcase(prm_line) eq "i31"
	group by
		time_slice
		,member_id
		,caseadmitid
	;
quit;

proc sql;
	create table post040.snf_readmissions as
	select distinct
		snf.time_slice
		,snf.member_id
		,snf.caseadmitid
	from snf_stays as snf
	inner join (
		select
			time_slice
			,member_id
			,caseadmitid
			,max(date_case_earliest) as date_acute_admit
		from Agg_med_cases_limited
		where lowcase(prm_line) ne "i31"
		group by
			time_slice
			,member_id
			,caseadmitid
		) as acute on
		snf.time_slice eq acute.time_slice
		and snf.member_id eq acute.member_id
		and (acute.date_acute_admit - snf.date_snf_discharge) between 2 and 30 /*Do not count immediate transfers.*/
	left join snf_stays as snf_interrupts on
		snf.time_slice eq snf_interrupts.time_slice
		and snf.member_id eq snf_interrupts.member_id
		and snf.caseadmitid ne snf_interrupts.caseadmitid
		/*Make sure there wasn't another SNF stay prior to the Acute admit*/
		and snf_interrupts.date_snf_admit between snf.date_snf_discharge and acute.date_acute_admit
	where snf_interrupts.member_id is null
	;
quit;
%LabelDataSet(post040.snf_readmissions)

%let readmit_rate = %sysfunc(round(%sysevalf(%GetRecordCount(post040.snf_readmissions)/%GetRecordCount(snf_stays)),0.0001));
%put readmit_rate = &readmit_rate.;
%AssertThat(&readmit_rate.,gt,0.01,ReturnMessage=Troublingly few readmissions were identified.)

%put return_code = &syscc.;
