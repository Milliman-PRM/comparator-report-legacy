/*
### CODE OWNERS: Anna Chen, Kyle Baird

### OBJECTIVE:
	Calculate the Other Outpatient Metrics.  

### DEVELOPER NOTES:
	According to CMS website, High-Tech Imaging includes CT, MRI and PET. 
	(https://www.cms.gov/Medicare/Provider-Enrollment-and-Certification/MedicareProviderSupEnroll/AdvancedDiagnosticImagingAccreditation.html)
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/*Library*/
libname M015_out "&M015_out." access=readonly;
libname post008 "&post008." access = readonly;
libname post010 "&post010." access = readonly;
libname post030 "&post030.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Create the current and prior dataset with only the metrics that we need and with only eligible members using the function call;*/
%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Force_Util=&post_force_util.
	,Dimensions=member_id~prm_line
	,Time_Slice=&list_time_period.
	,Where_Claims=%str(lowcase(Outclaims_prm.prm_line) eqt "o" or lowcase(Outclaims_prm.prm_line) in ("p32c","p32d"))
	,Suffix_Output=raw
	)

/*Limit members to those that apply to our time periods*/
proc sql;
	create table claims_members as
	select
		claims.*
	from agg_claims_med_raw as claims
	inner join post008.members as mems
		on claims.Member_ID = mems.Member_ID 
		and claims.time_slice = mems.time_period
	;
quit;

/***** CALCULATE METRICS *****/
/*** PCT OFFICE VISITS TO A PCP ***/
proc sql;
	create table pct_office_visits_pcp as
	select
		time_slice as time_period
		,"pct_office_visits_pcp" as metric_id length = 32 format = $32.
		,"% Primary Care Office Visits" as metric_name length = 256 format = $256.
		,sum(case when lowcase(prm_line) eq "p32c" then prm_util else 0 end) as _sum_visits_pcp
		,sum(prm_util) as _sum_visits_combined
		,calculated _sum_visits_pcp / calculated _sum_visits_combined as metric_value
	from claims_members
	where lowcase(prm_line) in ("p32c","p32d")
	group by time_slice
	;
quit;

/*** UTILIZATION RATES (NOT RISK ADJUSTED) ***/
data ref_service_agg;
	set M015_out.mr_line_info (keep =
		mr_line
		prm_line_desc /*For reference when developing.*/
		costmodel_util /*To check we do not mix util types*/
		);
	format
		metric_id $32.
		metric_name $256.
		;
	if lowcase(mr_line) in ("o14a","o14b","o14c") then do;
		metric_id = "high_tech_imaging_per1k";
		metric_name = "High Tech Imaging Utilization per 1000";
	end;
	else if lowcase(mr_line) eq "o41h" then do;
		metric_id = "observation_stays_per1k";
		metric_name = "Observation Stays Utilization per 1000";
	end;
	else delete;
run;

proc sql noprint;
	select
		max(cnt_distinct_util_types)
	into :max_cnt_distinct_util_types trimmed
	from (
		select
			metric_id
			,count(distinct costmodel_util) as cnt_distinct_util_types
			from ref_service_agg
			group by metric_id
		)
	;
quit;
%put max_cnt_distinct_util_types = &max_cnt_distinct_util_types.;
%AssertThat(
	&max_cnt_distinct_util_types.
	,eq
	,1
	,ReturnMessage=Requested aggregate categories contain a mix of utilization types.
	)

proc sql;
	create table agg_util as
	select
		claims.time_slice as time_period
		,ref_service_agg.metric_id
		,ref_service_agg.metric_name
		,sum(prm_util) as _sum_prm_util
	from claims_members as claims
	inner join ref_service_agg as ref_service_agg
		on claims.prm_line eq ref_service_agg.mr_line
	group by
		claims.time_slice
		,ref_service_agg.metric_id
		,ref_service_agg.metric_name
	;
quit;

proc transpose data = post010.metrics_basic
	out = memmos_riskscr (drop = _:)
	;
	where lowcase(metric_id) in (
		"riskscr_1_avg"
		,"memmos_sum"
		);
	by time_period;
	var metric_value;
	id metric_id;
run;

proc sql;
	create table util_rates as
	select
		agg_util.*
		,memmos_riskscr.memmos_sum as _sum_memmos
		,memmos_riskscr.riskscr_1_avg as _avg_riskscr
		,_sum_prm_util * (1 / memmos_riskscr.memmos_sum) * 12 * 1000 as metric_value
	from agg_util as agg_util
	left join memmos_riskscr as memmos_riskscr
		on agg_util.time_period eq memmos_riskscr.time_period
	;
quit;

/*** UTILIZATION RATES (RISK ADJUSTED) ***/
data util_rates_riskadj;
	set util_rates;
	metric_id = catx("_",metric_id,"riskadj");
	metric_name = catx(", ",metric_name,"Risk Adjusted");
	metric_value = metric_value * _avg_riskscr;
run;

/*** COMBINE THE RESULTS ***/
data post030.metrics_outpatient;
	format &metrics_key_value_cgfrmt.;
	set util_rates
		util_rates_riskadj
		pct_office_visits_pcp
		;
	by time_period;
	&assign_name_client.;
	metric_category = "outpatient";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post030.metrics_outpatient);

%put System Return Code = &syscc.;
