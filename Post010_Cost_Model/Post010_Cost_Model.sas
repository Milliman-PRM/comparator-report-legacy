/*
### CODE OWNERS: Kyle Baird

### OBJECTIVE:
	Use the PRM outputs to create a basic cost model.

### DEVELOPER NOTES:
	Rx claims and eligibility will not be included because their
	costs are not available in the CCLF data
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "%GetParentFolder(0)supp010_shared_code.sas";
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname outputs "&path_dir_outputs.";

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
%agg_claims(
	IncStart=&date_performanceyearstart.
	,IncEnd=&date_latestpaid.
	,PaidThru=&date_latestpaid.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Admit
	,Force_Util=N
	,Dimensions=prm_line~elig_status_1~prv_net_aco_yn
	,Time_Slice=
	,Where_Claims=
	,Where_Elig=
	,Date_DateTime=
	,Suffix_Output=
	)

data agg_claims_med_coalesce;
	set agg_claims_med;
	elig_status_1 = coalescec(elig_status_1,"N");
	prv_net_aco_yn = coalescec(prv_net_aco_yn,"N"); *Default to OON;
run;

%GetVariableInfo(agg_claims_med_coalesce,meta_variables)

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
	data = agg_claims_med_coalesce
	;
	class prm_line
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
data outputs.cost_util;
	format &cost_util_codegen_format.;
	set agg_claims_med_reagg;
	&assign_name_client.;
	prv_net_aco_yn = coalescec(prv_net_aco_yn,"N"); *Default to OON;
	if lowcase(prm_line) eq: "i" then prm_admits = admits;
	else prm_admits = 0;
	if lowcase(prm_line) eq: "i" then prm_days = prm_util;
	else prm_days = 0;
	prm_allowed = allowed;
	keep &cost_util_fields_space.;
run;
%LabelDataSet(outputs.cost_util)

data outputs.memmos;
	format &memmos_codegen_format.;
	set agg_memmos;
	&assign_name_client.;
	prm_memmos = memmos_medical;
	keep &memmos_fields_space.;
run;
%LabelDataSet(outputs.memmos)

data outputs.ref_prm_line;
	format &ref_prm_line_codegen_format.;
	set M015_out.mr_line_info;
	&assign_name_client.;
	prm_line = mr_line;
	prm_line_category = prm_line_desc1;
	prm_util_type = costmodel_util;
	keep &ref_prm_line_fields_space.;
run;
%LabelDataSet(outputs.ref_prm_line)

%put System Return Code = &syscc.;
