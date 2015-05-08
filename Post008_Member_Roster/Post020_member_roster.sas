/*
### CODE OWNERS: Kyle Baird

### OBJECTIVE:
	Create a centralized list of members who were assigned
	at the end of each time period.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

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

data member_roster;
	format time_period $16.;
	set M035_Out.member_time (keep =
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
		);
	where upcase(assignment_indicator) eq "Y" /*Limit to windows where members were assigned.*/
		and (
			upcase(cover_medical) eq "Y"
				or upcase(cover_rx) eq "Y"
			) /*Must have actually had coverage (gets rid of any "zombie periods")*/
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
	from member_roster as roster
	left join M035_Out.member as member
		on roster.member_id eq member.member_id
	left join post008.time_windows as time_windows
		on upcase(roster.time_period) eq upcase(time_windows.time_period)
	order by
		roster.member_id
		,roster.time_period
	;
quit;
%LabelDataSet(post008.members)

%put System Return Code = &syscc.;
