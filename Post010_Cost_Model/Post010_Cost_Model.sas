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
%include "%GetParentFolder(0)supp010_shared_code.sas";
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/***** METADATA AND CODEGEN *****/
%build_metadata_table(
	&name_datamart_target.
	,name_dset_out=metadata_target
	)

%macro generate_codegen_variables(name_table);
	%global &name_table._fields_space
		&name_table._codegen_format
		;
	proc sql noprint;
		select
			name_field
			,catx(
				" "
				,name_field
				,sas_format
				)
		into :&name_table._fields_space separated by " "
		,:&name_table._codegen_format separated by " "
		from metadata_target
		where upcase(name_table) eq "%upcase(&name_table.)"
		;
	quit;
	%put &name_table._fields_space = &&&name_table._fields_space.;
	%put &name_table._codegen_format = &&&name_table._codegen_format.;
%mend generate_codegen_variables;
/*
%generate_codegen_variables(memmos)
*/

proc sql;
	create table tables_target as
	select distinct
		name_table
	from metadata_target
	;
quit;

data _null_;
	set tables_target;
	call execute(
		cats(
			'%nrstr(%generate_codegen_variables(name_table='
			,name_table
			,'))'
			)
		);
run;

/***** GENERATE RAW SOURCE DATA *****/
proc sql noprint;
	select
		time_period
		,inc_start format = best12.
		,inc_end format = best12.
		,paid_thru format = best12.
	into :list_time_period separated by "~"
		,:list_inc_start separated by "~"
		,:list_inc_end separated by "~"
		,:list_paid_thru separated by "~"
	from post008.time_windows
	;
quit;
%put list_time_period = &list_time_period.;
%put list_inc_start = &list_inc_start.;
%put list_inc_end = &list_inc_end.;
%put list_paid_thru = &list_paid_thru.;

%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Discharge
	,Force_Util=N
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
	from agg_claims_med_coalesce as src
	inner join post008.members as limit on
		src.member_id eq limit.member_id
			and src.time_period eq limit.time_period
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
		prm_line
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
	format &cost_util_codegen_format.;
	set agg_claims_med_reagg;
	&assign_name_client.;
	if lowcase(prm_line) eq: "i" then prm_admits = Discharges;
	else prm_admits = 0;
	if lowcase(prm_line) eq: "i" then prm_days = prm_util;
	else prm_days = 0;
	prm_allowed = Allowed;
	prm_paid = paid;
	PRM_Coverage_Type = 'Medical';
	keep &cost_util_fields_space.;
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
	format &memmos_codegen_format.;
	set agg_memmos_long (rename = (time_slice = time_period));
	&assign_name_client.;
	prm_memmos = memmos1;
	prm_coverage_type = propcase(scan(Coverage_Type_Raw, 2 ,"_"));
	keep &memmos_fields_space.;
run;
%LabelDataSet(post010.memmos)

data post010.ref_prm_line;
	format &ref_prm_line_codegen_format.;
	set M015_out.mr_line_info;
	&assign_name_client.;
	prm_line = mr_line;
	prm_line_category = prm_line_desc1;
	prm_util_type = costmodel_util;
	keep &ref_prm_line_fields_space.;
run;
%LabelDataSet(post010.ref_prm_line)

%put System Return Code = &syscc.;
