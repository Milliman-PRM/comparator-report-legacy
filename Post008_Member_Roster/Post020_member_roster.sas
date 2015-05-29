/*
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
	Create a centralized list of members who were assigned
	at the end of each time period.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_Cde.Func04_run_hcc_wrap_prm.sas";
%include "&M008_Cde.Func05_run_mara_wrap_prm.sas";
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

/* Libnames */
libname M035_Out "&M035_Out." access = readonly;
libname post008 "&post008.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




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

proc sql noprint;
	create table memtime_w_riskscr_type as
		select time.*
				,mem.risk_score_type
	from M035_Out.member_time as time
	left join
		M035_Out.member as mem
		on time.member_ID = mem.member_ID
	;
quit;

data member_roster;
	format time_period $16.;
	set memtime_w_riskscr_type (keep =
		member_id
		assignment_indicator
		cover_medical
		cover_rx
		date_start
		date_end
		/*Any time-varying dimensions to keep*/
		elig_status_1
		mem_prv_id_align
		prv_name_align
		/*Fields pulled from member table*/
		risk_score_type
		);
	where upcase(assignment_indicator) eq "Y" /*Limit to windows where members were assigned.*/
		;

	/*Only output the windows that include then ending boundary of our time period.*/
	&codegen_member_selection.
	; *Just to get syntax highlighting in IDE;
	drop
		assignment_indicator
		cover_medical
		cover_rx
		date_start
		date_end
		;
run;
/*Should not happen because we do not allow overlapping time windows, but just in case.*/
%AssertNoDuplicates(
	member_roster
	,member_id time_period
	,ReturnMessage=Multiple time windows assigned for a given time period.
	)

/*Calculate Risk Scores to add to the member table*/
proc sql noprint;
	select 
		time_period
		,inc_start_riskscr_features format = 12.
		,inc_end_riskscr_features format = 12.
		,paid_thru format = 12.
	into :list_time_period_riskscr separated by "~"
		,:list_inc_start_riskscr separated by "~"
		,:list_inc_end_riskscr separated by "~"
		,:list_paid_thru_riskscr separated by "~"
	from post008.Time_windows
	;
quit;
%put list_time_period_riskscr = &list_time_period_riskscr.;
%put list_inc_start_riskscr = &list_inc_start_riskscr.;
%put list_inc_end_riskscr = &list_inc_end_riskscr.;
%put list_paid_thru_riskscr = &list_paid_thru_riskscr.;

proc sql noprint;
	select count(distinct member_ID)
	into :cnt_HCC_mems trimmed
	from member_roster
	where upcase(risk_score_type) eq upcase("CMS HCC Risk Score")
	;
	select count(distinct member_ID)
	into :cnt_MARA_mems trimmed
	from member_roster
	where upcase(risk_score_type) eq upcase("MARA Risk Score")
	;
quit;
%put cnt_HCC_mems = &cnt_HCC_mems.;
%put cnt_MARA_mems = &cnt_MARA_mems.;

%MockLibrary(riskscr)

%macro Calc_Risk_Scores ();

	%if &cnt_HCC_mems. gt 0 %then %do;

		%run_hcc_wrap_prm(&list_inc_start_riskscr.
				,&list_inc_end_riskscr.
				,&list_paid_thru_riskscr.
				,&list_time_period_riskscr.
				,riskscr
				)
	%end;

	%else %do; 
		proc sql noprint;
			create table riskscr.hcc_results (
			    time_slice 			char	format= $32. 
				,hicno 				char	format= $40.
				,score_community 	num		format= best12.
				);
		quit;		
	%end;

	%if &cnt_MARA_mems. gt 0 %then %do;

		%run_mara_wrap_prm(&list_inc_start_riskscr.
				,&list_inc_end_riskscr.
				,&list_paid_thru_riskscr.
				,&list_time_period_riskscr.
				,riskscr
				,list_models=DXPROLAG0~DXCONLAG0
				)

		proc sql;
			create table riskscr.mara_scores_limited as
			select
				scores.*
			from riskscr.mara_scores as scores
			inner join post008.time_windows as windows
				on scores.time_slice eq windows.time_period
					and upcase(substr(scores.model_name,3,3)) eq upcase(substr(windows.riskscr_period_type,1,3))
			order by
				scores.member_id
				,scores.time_slice
			;
		quit;
	%end;

	%else %do;
		proc sql noprint;
			create table riskscr.mara_scores_limited (
			    time_slice 			char	format= $32.
				,model_name char format = $16.
				,member_id 			char	format= $40.
				,riskscr_tot	 	num		format= best12.
				);
		quit;	
	%end;

%mend Calc_Risk_Scores;

%Calc_Risk_Scores()

/*Pull in member months to append to the member roster
	This utilizes potentially different time periods from risk scores above.*/
%agg_memmos(&list_inc_start.
		,&list_inc_end.
		,member_id
		,&list_time_period.
		)

/*Decorate roster with information from member that may be needed
  for subsequent analyses (e.g. risk scoring)*/
proc sql;
	create table post008.members as
	select
		roster.*
		,member.dob
		,member.gender
		,member.mem_name
		/*Re-calc age at time of period end*/
/*		,time_windows.inc_end*/
		,case
			when member.dob gt time_windows.inc_end then 0
			else floor(
				yrdif(
					member.dob
					,time_windows.inc_end
					,"age"
					)
				)
			end as age
		,coalesce(memmos.memmos_medical,0) as memmos
		,member.risk_score_type as riskscr_1_type
		,case when upcase(member.risk_score_type) = upcase("CMS HCC Risk Score")
					then hcc_rs.score_community
				when upcase(member.risk_score_type) = upcase("MARA Risk Score")
					and upcase(substr(time_windows.riskscr_period_type,1,3)) = upcase(substr(mara_rs.model_name,3,3))
					then mara_rs.riskscr_tot
				else .
			end as riskscr_1

	from member_roster as roster
	left join M035_Out.member as member
		on roster.member_id eq member.member_id
	left join post008.time_windows as time_windows
		on upcase(roster.time_period) eq upcase(time_windows.time_period)
	left join riskscr.hcc_results as hcc_rs
		on upcase(roster.time_period) eq upcase(hcc_rs.time_slice) and roster.member_id eq hcc_rs.hicno
	left join riskscr.mara_scores_limited as mara_rs
		on upcase(roster.time_period) eq upcase(mara_rs.time_slice) and roster.member_id eq mara_rs.member_id
	left join agg_memmos as memmos
		on roster.member_id = memmos.member_id and upcase(roster.time_period) = upcase(memmos.time_slice)
	order by
		roster.member_id
		,roster.time_period
	;
quit;
%LabelDataSet(post008.members)

%assertthat(%getrecordcount(member_roster),eq,%getrecordcount(post008.members),ReturnMessage=The SQL step added rows to the table)

%put System Return Code = &syscc.;
