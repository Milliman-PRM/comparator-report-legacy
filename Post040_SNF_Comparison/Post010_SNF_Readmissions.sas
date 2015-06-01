/*
### CODE OWNERS: Jason Altieri, Shea Parkes

### OBJECTIVE:
	Identify SNF stays that failed
		(i.e. fell in the middle of a Medicare 30-day all cause re-admit).

### DEVELOPER NOTES:
	This program is not vectorized by time_period because the failure windows can bleed over the time window edges.
	It was easier to just compute these answers without vectorization and join them to the vectorized results in the next program.
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;
%Include "&M008_Cde.Func02_massage_windows.sas" / source2;

libname post040 "&post040.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/**** BROAD AGG_CLAIMS() CALL TO GET INTERESTING DATA ****/

%Agg_Claims(
	IncStart=&Date_CredibleStart.
	,IncEnd=%sysfunc(mdy(12,31,9999))
	,PaidThru=%sysfunc(mdy(12,31,9999))
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=member_ID~prm_line~caseadmitid~PRM_Readmit_All_Cause_YN~PRM_Readmit_All_Cause_CaseID
	,Force_Util=&post_force_util.
	,where_claims= %str(lowcase(outclaims_prm.prm_line) eqt "i")
	,output_suffix = time
    );




/**** FIND WINDOWS OF FAILURE ****/

proc sql;
	create table failure_windows_sloppy as
	select distinct /*No need for any duplicate information*/
		index.member_id
		,index.date_case_latest as fail_window_start
		,readmit.date_case_earliest as fail_window_end
	from agg_claims_med_time(where = (
		lowcase(prm_line) ne 'i31'
		and upcase(PRM_Readmit_All_Cause_YN) eq 'Y'
		)) as index
	left join agg_claims_med_time as readmit on
		index.member_id eq readmit.member_id
		and index.PRM_Readmit_All_Cause_CaseID eq readmit.caseadmitid
	order by
		index.member_id
		,index.date_case_latest
	;
quit;

%AssertNoNulls(failure_windows_sloppy, fail_window_end,ReturnMessage=Not all linkages were found.)

%massage_windows(
	failure_windows_sloppy
	,failure_windows
	,fail_window_start
	,fail_window_end
	,member_id
	)



	
/**** FIND SNF FAILURES ****/

proc sql;
	create table snf_stays as
	select
		member_id
		,caseadmitid
		,max(date_case_latest) as date_discharge_snf
	from agg_claims_med_time
	where lowcase(prm_line) eq "i31"
	group by
		member_id
		,caseadmitid
	order by
		member_id
		,caseadmitid
	;
quit;

proc sql;
	create table post040.snf_readmissions as
	select
		snf.member_id
		,snf.caseadmitid
	from snf_stays as snf
	inner join failure_windows as fails on
		snf.member_id eq fails.member_id
		and snf.date_discharge_snf between fails.fail_window_start and fails.fail_window_end
	order by
		snf.member_id
		,snf.caseadmitid
	;
quit;
%LabelDataSet(post040.snf_readmissions)

%AssertNoDuplicates(post040.snf_readmissions,Member_ID CaseAdmitID,ReturnMessage=Unexpected cartesianing occured.)

%let readmit_rate = %sysfunc(round(%sysevalf(%GetRecordCount(post040.snf_readmissions)/%GetRecordCount(snf_stays)),0.0001));
%put readmit_rate = &readmit_rate.;
%AssertThat(&readmit_rate.,gt,0.01,ReturnMessage=Troublingly few readmissions were identified.)

%put return_code = &syscc.;
