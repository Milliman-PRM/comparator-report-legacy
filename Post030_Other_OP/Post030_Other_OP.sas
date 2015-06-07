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
%include "&M073_Cde.pudd_methods\*.sas";

/*Library*/
libname M015_out "&M015_out." access=readonly;
libname post008 "&post008." access = readonly;
libname post009 "&post009." access = readonly;
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
		,mems.elig_status_1
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
		,elig_status_1
		,"pct_office_visits_pcp" as metric_id length = 32 format = $32.
		,"% Primary Care Office Visits" as metric_name length = 256 format = $256.
		,sum(case when lowcase(prm_line) eq "p32c" then prm_util else 0 end) as _sum_visits_pcp
		,sum(prm_util) as _sum_visits_combined
		,calculated _sum_visits_pcp / calculated _sum_visits_combined as metric_value
	from claims_members
	where lowcase(prm_line) in ("p32c","p32d")
	group by time_slice
			,elig_status_1
	;
quit;

/*** UTILIZATION RATES ***/
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
	create table agg_util_mcrm as
	select
		claims.time_slice as time_period
		,claims.elig_status_1
		,ref_service_agg.metric_id
		,ref_service_agg.metric_name
		,mr_to_mcrm.mcrm_line
		,sum(prm_util) as _sum_prm_util
	from claims_members as claims
	inner join ref_service_agg as ref_service_agg
		on claims.prm_line eq ref_service_agg.mr_line
	left join M015_out.link_mr_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as mr_to_mcrm on
		claims.prm_line eq mr_to_mcrm.mr_line
	group by
		claims.time_slice
		,claims.elig_status_1
		,ref_service_agg.metric_id
		,ref_service_agg.metric_name
		,mr_to_mcrm.mcrm_line
	;
quit;

proc sql;
	create table agg_util as
	select
		src.time_period
		,src.elig_status_1
		,src.metric_id
		,src.metric_name
		,sum(src._sum_prm_util) as _sum_prm_util
		,sum(src._sum_prm_util / risk.riskscr_1_util_avg) as _sum_prm_util_riskadj
	from agg_util_mcrm as src
	left join post009.riskscr_service as risk on
		src.time_period eq risk.time_period
			and src.elig_status_1 eq risk.elig_status_1
			and src.mcrm_line eq risk.mcrm_line
	group by
		src.time_period
		,src.elig_status_1
		,src.metric_id
		,src.metric_name
	;
quit;

proc transpose data = post010.metrics_basic
	out = memmos (drop = _:)
	;
	where lowcase(metric_id) in (
		"memmos_sum"
		);
	by time_period elig_status_1;
	var metric_value;
	id metric_id;
run;

proc sql;
	create table util_rates_wide as
	select
		agg_util.*
		,memmos.memmos_sum as _sum_memmos
		,_sum_prm_util * (1 / memmos.memmos_sum) * 12 * 1000 as util_rate_raw
		,_sum_prm_util_riskadj * (1 / memmos.memmos_sum) * 12 * 1000 as util_rate_riskadj
	from agg_util as agg_util
	left join memmos as memmos
		on agg_util.time_period eq memmos.time_period
		and agg_util.elig_status_1 eq memmos.elig_status_1
	order by
		agg_util.time_period
		,agg_util.elig_status_1
	;
quit;

data util_rates;
	set util_rates_wide;
	metric_value = util_rate_raw;
	output;
	call missing(metric_value);
	metric_id = catx("_",metric_id,"riskadj");
	metric_name = catx(", ",metric_name,"Risk Adjusted");
	metric_value = util_rate_riskadj;
	output;
	drop _:;
run;

/*** COMBINE THE RESULTS ***/
data post030.metrics_outpatient;
	format &metrics_key_value_cgfrmt.;
	set util_rates
		pct_office_visits_pcp
		;
	by time_period elig_status_1;
	&assign_name_client.;
	metric_category = "outpatient";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post030.metrics_outpatient);

%put System Return Code = &syscc.;
