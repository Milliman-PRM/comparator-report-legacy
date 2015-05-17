/*
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
	Use the PRM outputs to create a basic cost model.

### DEVELOPER NOTES:
	Rx claims and eligibility will not be included because their
	costs are not available in the CCLF data
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/***** GENERATE RAW SOURCE DATA *****/

%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Force_Util=&post_force_util.
	,Dimensions=member_id~prm_line~elig_status_1~prv_net_aco_yn
	,Time_Slice=&list_time_period.
	,Where_Claims=
	,Where_Elig=
	,Date_DateTime=
	,Suffix_Output=member
	)

data agg_claims_med_coalesce;
	set agg_claims_med_member;
	elig_status_1 = coalescec(elig_status_1,"Unknown");
	prv_net_aco_yn = coalescec(prv_net_aco_yn,"N"); *Default to OON;
	rename time_slice = time_period;
run;

proc sql;
	create table agg_claims_med_limited as
	select
		src.*
		,mrl.mcrm_line

	from agg_claims_med_coalesce as src
	inner join post008.members as limit on
		src.member_id eq limit.member_id
			and src.time_period eq limit.time_period
	left join M015_Out.mr_line_info as mrl on
		src.prm_line = mrl.mr_line
	;
quit;

%GetVariableInfo(agg_claims_med_limited,meta_variables)

proc sql noprint;
	select
		varname
	into :agg_claims_measures separated by " "
	from meta_variables
	where upcase(vartype) eq "N"
		and upcase(varname) net "DATE_"
	;
quit;
%put agg_claims_measures = &agg_claims_measures.;

proc means noprint
	nway
	missing
	data = agg_claims_med_limited
	;
	class time_period
		mcrm_line
		elig_status_1
		prv_net_aco_yn
		;
	var &agg_claims_measures.;
	output out = agg_claims_med_reagg (drop =
		_TYPE_
		_FREQ_
		)
		sum =
		;
run;

/***** CREATE FINAL OUTPUTS *****/
data post010.cost_util;
	format &cost_util_cgfrmt.;
	set agg_claims_med_reagg;
	&assign_name_client.;
	if lowcase(mcrm_line) eq: "i" then prm_discharges = Discharges;
	else prm_discharges = 0;
	if lowcase(mcrm_line) eq: "i" then prm_days = prm_util;
	else prm_days = 0;
	prm_allowed = Allowed;
	prm_paid = paid;
	PRM_Coverage_Type = 'Medical';
	keep &cost_util_cgflds.;
run;
%LabelDataSet(post010.cost_util)

proc sql;
	create table agg_memmos_limited as
	select
		src.*
	from agg_memmos_member as src
	inner join post008.members as limit on
		src.member_id eq limit.member_id
			and src.time_slice eq limit.time_period
	;
quit;

proc means
	noprint
	nway
	missing
	data = agg_memmos_limited
	;
	class
		time_slice
		elig_status_1
		;
	var _numeric_;
	output out = agg_memmos_reagg (
		drop = _TYPE_
			_FREQ_
		)
		sum =
		;
run;

proc sort data=agg_memmos_reagg out=agg_memmos_dimsort;
	by _character_;
run;

proc transpose
		data=agg_memmos_dimsort
		out=agg_memmos_long
		name=Coverage_Type_Raw
		prefix=memmos
		;
	by _character_;
	var memmos_:;
run;

data post010.memmos;
	format &memmos_cgfrmt.;
	set agg_memmos_long (rename = (time_slice = time_period));
	&assign_name_client.;
	prm_memmos = memmos1;
	prm_coverage_type = propcase(scan(Coverage_Type_Raw, 2 ,"_"));
	keep &memmos_cgflds.;
run;
%LabelDataSet(post010.memmos)

data ref_mcrm_line_dups;
	format &ref_mcrm_line_cgfrmt.;
	set M015_out.mr_line_info;
	&assign_name_client.;
	prm_util_type = costmodel_util;
	keep &ref_mcrm_line_cgflds.;
run;

proc sql;
	create table post010.ref_mcrm_line as
	select distinct
		*
	from ref_mcrm_line_dups
	;
quit;
%LabelDataSet(post010.ref_mcrm_line)
%AssertNoDuplicates(
	post010.ref_mcrm_line
	,name_client mcrm_line
	,ReturnMessage=MCRM lines are not properly de-duplicated.
	)

%put System Return Code = &syscc.;
