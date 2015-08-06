/*
### CODE OWNERS: Michael Menser, Shea Parkes, Jason Altieri

### OBJECTIVE:
	Create the memcnt table from the member roster.

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

libname M180_Out "&M180_Out." access=readonly;
libname post008 "&post008.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/**** CODEGEN QUALITY METRIC WORK ****/


/*Stuck in dataset because Proc SQL does not enjoy regex on dictionary views.*/
data puad_quality_metrics;
	set sashelp.vcolumn;
	where
		upcase(libname) eq 'M180_OUT'
		and prxmatch("/Puad\d{2}_member_excluded/i", strip(memname))
		and prxmatch('/endoflife_(numer|denom)_yn_/i', name)
		;
run;

proc sql noprint;
	select
		catx('.', 'decedents', name)
		,cat(
			'coalesce('
			,catx('.', 'decedents', name)
			,',"N") as '
			,strip(name)
			)
	into 
		:puad_quality_metrics_select separated by ','
		,:puad_quality_metrics_coalesce separated by ','
	from puad_quality_metrics
	;
quit;

%put puad_quality_metrics_select = &puad_quality_metrics_select.;
%put puad_quality_metrics_coalesce = &puad_quality_metrics_coalesce.;
	


/**** DECEDENT CALCULATIONS ****/

proc sql noprint;
	select
		time_period
		,(inc_start - 90) format = best12. /*Reach back further for prior-to-death costs.*/
		,inc_end format = best12.
		,paid_thru format = best12.
	into :eol_time_period separated by "~"
		,:eol_inc_start separated by "~"
		,:eol_inc_end separated by "~"
		,:eol_paid_thru separated by "~"
	from post008.time_windows
	;
quit;
%put list_time_period = &list_time_period.;
%put eol_time_period = &eol_time_period.;

%put list_inc_start = &list_inc_start.;
%put eol_inc_start = &eol_inc_start.;

%put list_inc_end = &list_inc_end.;
%put eol_inc_end = &eol_inc_end.;

%put eol_paid_thru = &eol_paid_thru.;
%put list_paid_thru = &list_paid_thru.;
	

%agg_claims(
	IncStart=&eol_inc_start.
	,IncEnd=&eol_inc_end.
	,PaidThru=&eol_paid_thru.
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Force_Util=&post_force_util.
	,Dimensions=member_id~dischargestatus~prm_todate~prm_line
	,Time_Slice=&eol_time_period.
	,suffix_output = wide
	)

proc means data = post008.members noprint;
	class elig_status_1;
	var age;
	output out = avg_age (drop = _FREQ_ _TYPE_) mean = ;
run;

proc sql;
	create table decedents_agg_recent as
	select
		roster.member_id
		,roster.time_period
		,&puad_quality_metrics_select.
		,case
			when decedents.latest_hospice_date_discharge is null then 0
			when abs(decedents.death_date_excluded - decedents.latest_hospice_date_discharge) lt 3 then /*Fuzzy match due to different source systems.*/
				decedents.latest_hospice_date_discharge - decedents.latest_hospice_date_admit + 1
			else 0 end as final_hospice_days
		,coalesce(sum(claims.PRM_Costs), 0) as costs_final_30_days
		,case
			when max(case
				when claims.member_id is null then 0
				when lowcase(claims.prm_line) eq 'i31' then 0
				when upcase(claims.prm_line) net 'I' then 0
				when claims.DischargeStatus eq '20' then 1
				else 0 end) eq 1 then 'Y'
			else 'N' end as deceased_hospital_yn
		,age.age
	from post008.members as roster
	left join post008.time_windows as windows on
		roster.time_period eq windows.time_period
	inner join M180_Out.Puad12_member_excluded as decedents
		on roster.member_id = decedents.member_id_excluded
		and decedents.death_date_excluded between windows.inc_start and windows.inc_end
	left join agg_claims_med_wide as claims on
		roster.time_period eq claims.time_slice
		and roster.member_id eq claims.member_id
		and (decedents.death_date_excluded - claims.prm_todate) between 0 and 30
	left join avg_age as age
		on age.elig_status_1 eq roster.elig_status_1
	where
		decedents.death_date_excluded ne .
	group by
		roster.member_id
		,roster.time_period
		,&puad_quality_metrics_select.
		,final_hospice_days
	order by
		roster.member_id
		,roster.time_period
	;
quit;

%AssertNoDuplicates(decedents_agg_recent,member_id time_period,ReturnMessage=Extra records were created.)




/**** GENERATE CLEAN MEMCNT TABLE ****/
	
proc sql;
	create table memcnt_to_export as
	select
		"&name_client." as name_client
		,mems.time_period
		,mems.elig_status_1
		,case when decedents.member_id is not null then 'Y' else 'N' end as deceased_yn
		,coalesce(decedents.deceased_hospital_yn, 'N') as deceased_hospital_yn
		,&puad_quality_metrics_coalesce.
		,coalesce(decedents.final_hospice_days, 0) as final_hospice_days
		,sum(coalesce(decedents.costs_final_30_days, 0)) as costs_final_30_days_sum
		,mems.riskscr_1_type as risk_score_type
		,sum(mems.memmos) as riskscr_wgt
		,sum(mems.riskscr_1 * mems.memmos) / calculated riskscr_wgt as riskscr_avg
		,count(*) as memcnt
		,sum(case when mems.riskscr_memmos ge 3 then mems.memmos else 0 end) / calculated riskscr_wgt as riskscr_cred
	from post008.Members as mems
	left join decedents_agg_recent as decedents
		on mems.member_id = decedents.member_id 
		and mems.time_period = decedents.time_period
	group by
		mems.time_period
		,elig_status_1
		,deceased_yn
		,deceased_hospital_yn
		,&puad_quality_metrics_select.
		,risk_score_type
		,final_hospice_days
	;
quit;


proc sql noprint;
	select sum(memcnt)
	into :chksum_memcnt trimmed
	from memcnt_to_export
	;
quit;
%AssertRecordCount(post008.Members,eq,&chksum_memcnt.,ReturnMessage=Not all members were counted in the MemCnt table.)


data post008.memcnt;
	format &memcnt_cgfrmt.;
	set memcnt_to_export;
	keep &memcnt_cgflds.;
run;

%LabelDataSet(post008.memcnt);

proc sql;
	create table decedent_check as
	select
		*
	from post008.memcnt
	where 
		deceased_yn = "N" and 
			(
				deceased_hospital_yn eq "Y"
				or endoflife_numer_yn_chemolt14days eq "Y"
				or endoflife_denom_yn_chemolt14days eq "Y"
				or endoflife_numer_yn_hospicelt3day eq "Y"
				or endoflife_denom_yn_hospicelt3day eq "Y"
				or endoflife_numer_yn_hospicenever eq "Y"
				or endoflife_denom_yn_hospicenever eq "Y"
				or final_hospice_days ne 0
				or costs_final_30_days_sum ne 0
			)
	;
quit;

%AssertDatasetNotPopulated(decedent_check,ReturnMessage=Members that are not deceased have populated decendent decorators.);

%put return_code = &syscc.;
