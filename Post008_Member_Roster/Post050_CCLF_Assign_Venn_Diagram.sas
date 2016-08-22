/*
### CODE OWNERS: Shea Parkes, Michael Menser

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

%AssertNoDuplicates(periods_assign,member_id time_period,ReturnMessage=Duplicate member and time window records created.)



/**** FIND TIMELINE OF CCLF INCLUSION ****/
/* Look to the raw-stacked CCLF8 (Bene Rosters)
	and find the nearest date_latestpaid for each time_period*/

proc sql;
	create table cclf_periods_all as
	select
		cclf.date_latestpaid /*Vectorized*/
		,periods.time_period
		,periods.inc_end
		,abs(cclf.date_latestpaid - periods.inc_end) as difference
	from (
		select distinct date_latestpaid
		from M035_Out.Member_Raw_Stack
		) as cclf
	cross join post008.time_windows as periods
	order by
		time_period
		,difference
		,date_latestpaid desc
	;
quit;

data cclf_period_nearest;
	set cclf_periods_all;
	by time_period;
	if first.time_period;
run;

proc sql;
	create table periods_cclf as
	select
		src.member_id
		,memtime.elig_status_1
		,periods.time_period
		,max(case when src.death_date is not null then 1 else 0 end) as died_in_period
	from (
		/*
			Do the xrefing in a subquery to keep the outer query more sane.
			Squash the multiple hospice lines at the same time (redundantly squashed in parent query).
		*/
		select
			coalesce(xref.crnt_hic_num, raw.bene_hic_num) as member_id format=$40. length=40
			,raw.date_latestpaid
			,max(raw.bene_death_dt) as death_date
		from M035_Out.Member_Raw_Stack as raw
		left join (
			select distinct crnt_hic_num, prvs_hic_num
			from M020_Out.CCLF9_bene_xref 
			)as xref on
			raw.bene_hic_num eq xref.prvs_hic_num
		group by
			member_id
			,date_latestpaid
		) as src
	/*Intentionally cause some filtering and cartesianing with this join to get to time_period basis.*/
	inner join cclf_period_nearest as periods on
		src.date_latestpaid eq periods.date_latestpaid
	/*Reach out to processed data for timeline eligibility status*/
	left join M035_Out.member_time as memtime on
		src.member_id eq memtime.member_id
		and periods.inc_end between memtime.date_start and memtime.date_end
	group by
		src.member_id
		,memtime.elig_status_1
		,periods.time_period
	;
quit;

%AssertNoNulls(periods_cclf,elig_status_1,ReturnMessage=Raw CCLF sources did not all map to processed eligibility statuses.)
%AssertNoDuplicates(periods_cclf,time_period member_id elig_status_1,ReturnMessage=Staged CCLF data does not have anticipated structure.)



/**** CALCULATE EACH WING OF THE VENN-DIAGRAM ****/
/* Have to do each side separately because one direction can't include elig_status_1. */

proc sql;
	create table metrics_no_assign as
	select
		cclf.time_period
		,cclf.elig_status_1
		,'Count of CCLF Members with Assignment Information' as metric_name
		,'cnt_cclf_mems_in_assignment' as metric_id
		,sum(case when assign.member_id is null then 0 else 1 end) as metric_value
	from periods_cclf(where = (died_in_period eq 0)) as cclf
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

proc sql;
	create table metrics_raw_assign_cnt as
	select
		time_period
		,'All' as elig_status_1
		,'Count of Assigned Members' as metric_name
		,'cnt_assigned_mems' as metric_id
		,count(*) as metric_value
	from periods_assign
	group by time_period
	order by time_period
	;
quit;



/**** LIGHT VALIDATION AND OUTPUT ****/

*Only validate against the most recent time period;
proc sql noprint;
	select max(time_period)
	into :max_time_period trimmed
	from metrics_no_cclf
	;
quit;

%put &=max_time_period.;


proc sql;
	create table metrics_no_assign_validation as
	select
		cclf.time_period
		,cclf.elig_status_1
		,avg(case when assign.member_id is null then 0 else 1 end) as metric_value
	from periods_cclf(where = (died_in_period eq 0)) as cclf
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


proc sql noprint;
	select
		round(metric_value,0.0001)
	into 
		:pct_cclf_mems_in_assignment trimmed
	from metrics_no_assign_validation
	where upcase(elig_status_1) eq 'AGED NON-DUAL' and time_period eq "&max_time_period." /* Ignore metric for all but the majority of FFS Medicare lives, which are Aged Non-Dual */
	;
quit;
%put &=pct_cclf_mems_in_assignment.;
%AssertThat(&pct_cclf_mems_in_assignment.,le,1,ReturnMessage=An inprobable percentage of CCLF members were found in the assignment files.)
%AssertThat(&pct_cclf_mems_in_assignment.,gt,0.1,ReturnMessage=An inprobable percentage of CCLF members were found in the assignment files.)


proc sql noprint;
	select
		round(metric_value,0.0001)
	into 
		:pct_assigned_mems_in_cclf trimmed
	from metrics_no_cclf
	where time_period eq "&max_time_period."
	;
quit;
%put &=pct_assigned_mems_in_cclf.;

/*When this assertion is ran on a subset of a population, it is not unreasonable for there to be a group that has 100% assigned members in CCLF.
  Therefore, only run this assertion if the code is not being ran on a subset of the population.  The table M035_Out.Member_all will only be present
  when a subset is being ran (the table is a copy of the original combined Member table).*/
%macro run_type;

	%if %sysfunc(exist(M035_Out.Member_all)) eq 0 and %upcase(&cclf_ccr_absent_any_prior_cclf8.) eq INCLUDE %then %do;
		%AssertThat(&pct_assigned_mems_in_cclf.,lt,1,ReturnMessage=An inprobable percentage of Assigned members were found in the CCLF data.)
	%end;

%mend run_type;

%run_type

%AssertThat(&pct_assigned_mems_in_cclf.,gt,0.2,ReturnMessage=An inprobable percentage of Assigned members were found in the CCLF data.)


data post008.metrics_cclf_assign;
	format &metrics_key_value_cgfrmt.;
	set 
		metrics_no_assign
		metrics_no_cclf
		metrics_raw_assign_cnt
		;
	by time_period elig_status_1;
	&assign_name_client.;
	metric_category = "Basic";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post008.metrics_cclf_assign)

%put System Return Code = &syscc.;
