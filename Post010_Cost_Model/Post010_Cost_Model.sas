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

%let limit_lob = upcase(lob) eq "%upcase(&type_benchmark_hcg.)";
%put limit_lob = &limit_lob.;

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
	,Suffix_Output=member
	)

%macro conditional_rx;
	%if %upcase(&rx_claims_exist.) eq YES %then %do;
		%agg_claims(
			IncStart=&list_inc_start.
			,IncEnd=&list_inc_end.
			,PaidThru=&list_paid_thru.
			,Med_Rx=Rx
			,Ongoing_Util_Basis=&post_ongoing_util_basis.
			,Force_Util=&post_force_util.
			,Dimensions=member_id~prm_line~elig_status_1~prv_net_aco_yn
			,Time_Slice=&list_time_period.
			,Suffix_Output=member
			)
	%end;
%mend conditional_rx;

%conditional_rx

data agg_claims_coalesce;
	set agg_claims_med_member (
		in = med
		drop =
			_prm_util_cases_only
			prm_util_per1kmemyrs
		)
		%sysfunc(ifc("%upcase(&rx_claims_exist.)" eq "YES"
			,agg_claims_rx_member (
				in = rx
				drop =
					units
					dayssupply
					quantitydispensed
				)
			,%str()
			))
		;
	elig_status_1 = coalescec(elig_status_1,"Unknown");
	prv_net_aco_yn = coalescec(prv_net_aco_yn,"N"); *Default to OON;
	array
		costs
		allowed
		paid
		;
	do over costs;
		costs = coalesce(costs,0); *Blanket coalesce costs to zero because not all data source provide allowed/paid (mostly for Rx claims);
	end;
	format prm_coverage_type $8.;
	if med then prm_coverage_type = "Medical";
	else prm_coverage_type = "Rx";
	rename time_slice = time_period;
run;

proc sql;
	create table agg_claims_limited as
	select
		src.*
		,link_mr_mcrm_line.mcrm_line

	from agg_claims_coalesce as src
	inner join post008.members as limit on
		src.member_id eq limit.member_id
			and src.time_period eq limit.time_period
	left join M015_Out.link_mr_mcrm_line (where = (&limit_lob.)) as link_mr_mcrm_line on
		src.prm_line = link_mr_mcrm_line.mr_line
	;
quit;

/*Write this out so it can be used in the CPD program*/
data post010.agg_claims_limited;
	set agg_claims_limited;
run;

%GetVariableInfo(agg_claims_limited,meta_variables)

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
	data = agg_claims_limited
	;
	class time_period
		prm_line
		mcrm_line
		elig_status_1
		prv_net_aco_yn
		prm_coverage_type
		;
	var &agg_claims_measures.;
	output out = agg_claims_reagg (drop =
		_TYPE_
		_FREQ_
		)
		sum =
		;
run;

/***** CREATE FINAL OUTPUTS *****/
data post010.cost_util;
	format &cost_util_cgfrmt.;
	set agg_claims_reagg;
	&assign_name_client.;
	if lowcase(prm_line) eq: "i" then prm_discharges = Discharges;
	else prm_discharges = 0;
	if lowcase(prm_line) eq: "i" then prm_days = prm_util;
	else prm_days = 0;
	prm_allowed = Allowed;
	prm_paid = paid;
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

proc sql;
	create view ref_prm_mcrm_line as
	select
		ref_mr_line.mr_line
		,ref_mr_line.prm_line_desc
		,link.mcrm_line
		,ref_mcrm_line.mcrm_line_desc_l1
		,ref_mcrm_line.mcrm_line_desc_l2
		,ref_mcrm_line.mcrm_line_desc_l3
		,ref_mcrm_line.mcrm_line_desc_l4
		,ref_mcrm_line.mcrm_line_desc_l5
		,ref_mcrm_line.mcrm_line_desc_l6
		,ref_mr_line.costmodel_util
		,ref_mr_line.prm_coverage_type
	from M015_out.mr_line_info as ref_mr_line
	inner join M015_out.link_mr_mcrm_line (where = (&limit_lob.)) as link on
		ref_mr_line.mr_line eq link.mr_line
	left join M015_out.ref_mcrm_line as ref_mcrm_line on
		link.lob eq ref_mcrm_line.lob
			and link.mcrm_line eq ref_mcrm_line.mcrm_line
	order by ref_mr_line.mr_line
	;
quit;

data post010.ref_prm_line;
	format &ref_prm_line_cgfrmt.;
	set ref_prm_mcrm_line;
	prm_line = MR_Line;
	&assign_name_client.;
	prm_util_type = costmodel_util;
	keep &ref_prm_line_cgflds.;
run;

%LabelDataSet(post010.ref_prm_line)
%AssertNoDuplicates(
	post010.ref_prm_line
	,name_client prm_line
	,ReturnMessage=PRM lines are not properly de-duplicated.
	)

%put System Return Code = &syscc.;
