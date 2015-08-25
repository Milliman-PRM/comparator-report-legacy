/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Compare/contrast rosters from CCLF data and Assignment files.

### DEVELOPER NOTES:
	These metrics only make sense for clients with a CCLF data source.
	This metric is only calculated for clients with timeline assignment information.
	People missing from the CCLF data likely opted out of data sharing (or never opted in).
	People missing from the assignment file are likely those who signed a data sharing agreement upon request.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname M018_Out "&M018_Out." access=readonly;
libname M020_Out "&M020_Out." access=readonly;
libname M035_Out "&M035_Out." access=readonly;
libname post008 "&post008.";

%let elig_lookback_days = 30; /*Eligibility can be a bit jagged, so look back this many days.*/

%AssertThat(&Claims_Elig_Format.,eq,CCLF,ReturnMessage=The claims and eligibility format selected in the driver is not compatible with this program,FailAction=EndActiveSASSession);
%AssertDataSetPopulated(M018_Out.Client_Member_Time,ReturnMessage=This program requires timeline assignment information.,FailAction=EndActiveSASSession);

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/**** FIND TIMELINE OF ASSIGNED MEMBERS ****/
/* Must use source table that hasn't already been limited to CCLF roster. */

data codegen_member_selection;
	set post008.time_windows;
	format codegen_member_selection $256.;
	codegen_member_selection = cat(
		"if date_start le "
		,strip(put(inc_end,12.))
		," and date_end ge "
		,strip(put(inc_end,12.))
		," then do; time_period = '"
		,strip(time_period)
		,"'; output; end;"
		);
run;

proc sql noprint;
	select
		codegen_member_selection
	into :codegen_member_selection separated by " "
	from codegen_member_selection
	;
quit;
%put codegen_member_selection = %bquote(&codegen_member_selection.);

proc sql;
	create table timeline_assign_xref as
	select
		coalesce(xref.crnt_hic_num, src.member_id) as member_id format=$40. length=40
		,src.date_start
		,src.date_end
	from M018_Out.Client_Member_Time as src
	left join (
		select distinct crnt_hic_num, prvs_hic_num
		from M020_Out.CCLF9_bene_xref 
	)as xref on
		src.member_id eq xref.prvs_hic_num
	where upcase(assignment_indicator) eq "Y"
	;
quit;

data periods_assign;
	set timeline_assign_xref;
	format time_period $16.;
	&codegen_member_selection.
run;

%AssertNoDuplicates(assignment_buckets,member_id time_period,ReturnMessage=Duplicate member and time window records created.)



/**** FIND TIMELINE OF CCLF INCLUSION ****/
/* Time window ends are not clean, so need to check for any coverage in the last month. */

proc sql;
	create table periods_cclf as
	select distinct
		src.member_id
		,src.elig_status_1
		,periods.time_period
	from M035_Out.Member_Time as src
	inner join post008.time_windows as periods on
		src.date_start le periods.inc_end
		and src.date_end ge (periods.inc_end - &elig_lookback_days.)
	where upcase(src.cover_medical) eq 'Y'
	;
quit;



/**** CALCULATE EACH WING OF THE VENN-DIAGRAM ****/
/* Have to do each side separately because one direction can't include elig_status_1. */

proc sql;
	create table metrics_no_assign as
	select
		cclf.time_period
		,cclf.elig_status_1
		,'Percent of CCLF Members with Assignment Information' as metric_name
		,'pct_cclf_mems_in_assignment' as metric_id
		,avg(case when assign.member_id is null then 0 else 1 end) as metric_value
	from periods_cclf as cclf
	left join periods_assign as assign on
		cclf.time_period eq assign.time_period
		and cclf.member_id eq assign.member_id
	group by
		cclf.elig_status_1
		,cclf.time_period
	order by
		time_period
		,elig_status_1
	;
quit;

proc sql;
	create table metrics_no_cclf as
	select
		assign.time_period
		,'All' as elig_status_1
		,'Percent of Assigned Members with CCLF Information' as metric_name
		,'pct_assigned_mems_in_cclf' as metric_id
		,avg(case when cclf.member_id is null then 0 else 1 end) as metric_value
	from periods_assign as assign
	left join periods_cclf as cclf on
		assign.time_period eq cclf.time_period
		and assign.member_id eq cclf.member_id
	group by
		assign.time_period
	order by
		time_period
	;
quit;



/**** LIGHT VALIDATION AND OUTPUT ****/

proc sql noprint;
	select
		round(max(metric_value),0.0001)
		,round(min(metric_value),0.0001)
	into 
		:max_pct_cclf_mems_in_assignment trimmed
		,:min_pct_cclf_mems_in_assignment trimmed
	from metrics_no_assign
	;
quit;
%put &=max_pct_cclf_mems_in_assignment.;
%put &=min_pct_cclf_mems_in_assignment.;
%AssertThat(&max_pct_cclf_mems_in_assignment.,lt,1,ReturnMessage=An inprobable percentage of CCLF members were found in the assignment files.)
%AssertThat(&min_pct_cclf_mems_in_assignment.,gt,0.1,ReturnMessage=An inprobable percentage of CCLF members were found in the assignment files.)


proc sql noprint;
	select
		round(max(metric_value),0.0001)
		,round(min(metric_value),0.0001)
	into 
		:max_pct_assigned_mems_in_cclf trimmed
		,:min_pct_assigned_mems_in_cclf trimmed
	from metrics_no_cclf
	;
quit;
%put &=max_pct_assigned_mems_in_cclf.;
%put &=min_pct_assigned_mems_in_cclf.;
%AssertThat(&max_pct_assigned_mems_in_cclf.,lt,1,ReturnMessage=An inprobable percentage of Assigned members were found in the CCLF data.)
%AssertThat(&min_pct_assigned_mems_in_cclf.,gt,0.2,ReturnMessage=An inprobable percentage of Assigned members were found in the CCLF data.)


data post008.metrics_cclf_assign;
	format &metrics_key_value_cgfrmt.;
	set 
		metrics_no_assign
		metrics_no_cclf
		;
	by time_period elig_status_1;
	&assign_name_client.;
	metric_category = "Basic";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post008.metrics_cclf_assign)

%put System Return Code = &syscc.;
