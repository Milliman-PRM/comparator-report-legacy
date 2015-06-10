/*
### CODE OWNERS: Kyle Baird

### OBJECTIVE:
	Create client reference files for Pioneer ACOs

### DEVELOPER NOTES:
	Pioneer ACOs do not receive quarterly assignment files.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

%AssertThat(
	%upcase(&cclf_exclusion_criteria.)
	,eq
	,PIONEER
	,ReturnMessage=Only applicable for Pioneer ACOs.
	,FailAction=endactivesassession
	)

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname M020_Out "&M020_Out." access=readonly;
libname M035_Out "&M035_Out." access=readonly;
libname M018_Out "&M018_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/*** MAKE A ROSTER OF MEMBERS WITH ASSIGNMENT INFORMATION ***/
proc sql noprint;
	select
		max(date_latestpaid) format = best12.
	into :max_date_latestpaid_history trimmed
	from M035_out.member_raw_stack_warm_start
	;
quit;
%put max_date_latestpaid_history = &max_date_latestpaid_history. %sysfunc(putn(&max_date_latestpaid_history.,YYMMDDd10.));

%setup_xref

data members_all;
	set M035_out.member_raw_stack_warm_start
		M020_out.cclf8_bene_demog (in = current_month)
		;
	*Make a ficticious date_latestpaid for the current month.
	Does not have to be accurate just accurate enough so we can
	distinguish most recent.;
	if current_month then date_latestpaid = %sysfunc(intnx(month,&max_date_latestpaid_history.,1,same));
	%use_xref(bene_hic_num,member_id)
	drop bene_hic_num;
run;

/*Attempt to back into who is assigned.*/
proc sql noprint;
	select
		count(distinct date_latestpaid)
		,min(date_latestpaid)
		,max(date_latestpaid)
	into :cnt_date_latestpaid trimmed
		,:min_date_latestpaid trimmed
		,:max_date_latestpaid trimmed
	from members_all
	;
quit;
%put cnt_date_latestpaid = &cnt_date_latestpaid.;
%put min_date_latestpaid = &min_date_latestpaid. %sysfunc(putn(&min_date_latestpaid.,YYMMDDd10.));
%put max_date_latestpaid = &max_date_latestpaid. %sysfunc(putn(&max_date_latestpaid.,YYMMDDd10.));

proc sql;
	create table member_aggregates as
	select
		member_id
		,count(distinct date_latestpaid) as cnt_date_latestpaid
		,min(date_latestpaid) as min_date_latestpaid format = YYMMDDd10.
		,max(date_latestpaid) as max_date_latestpaid format = YYMMDDd10.
	from members_all
	group by member_id
	order by member_id
	;
quit;

proc sql;
	create table member_deaths as
	select
		member_id
		,min(date_latestpaid) as death_date_latestpaid format = YYMMDDd10.
	from members_all
	where bene_death_dt is not null
	group by member_id
	order by member_id
	;
quit;

proc sort data = members_all
	out = members_all_sort
	;
	by
		member_id
		descending date_latestpaid
		;
run;

data members_basic;
	set members_all_sort (
		keep =
			member_id
			date_latestpaid
		);
	by
		member_id
		descending date_latestpaid
		;
	if first.member_id;

	mem_dependent_status = "P";

	label mem_report_hier_1 = "All Members";
	mem_report_hier_1 = "All";
	label mem_report_hier_3 = "Not Implemented";
	mem_report_hier_3 = "Not Implemented";
	drop date_latestpaid;
run;

data members;
	merge
		members_basic (in = member_roster)
		member_aggregates (in = dates)
		member_deaths (in = deaths)
		;
	by member_id;
	if member_roster;
	label assignment_indicator = "Assigned Patient";
	*Verbose here to explain different categories for assignment;
	if cnt_date_latestpaid eq &cnt_date_latestpaid. then assignment_indicator = "Y";
	else if max_date_latestpaid eq &max_date_latestpaid. then assignment_indicator = "Y"; *Opt-Ins are assigned, but not reported.;
	else if max_date_latestpaid ne &max_date_latestpaid. then do;
		if death_date_latestpaid ne . then assignment_indicator = "Y"; *If they no longer show up because of death, then assigned.;
		else assignment_indicator = "N"; *Opt-outs/excluded are not assigned.;
	end;
run;

%put System Return Code = &syscc.;

