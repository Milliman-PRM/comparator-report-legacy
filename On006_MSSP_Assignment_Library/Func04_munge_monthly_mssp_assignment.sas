/*
### CODE OWNERS: Brandon Patterson

### OBJECTIVE:
	Generate a monthly eligibility table from the new CMS assignment file data

### DEVELOPER NOTES:
	
*/

/* Run these lines if testing interactively. 
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
libname M017_Out "&M017_Out.";
libname M018_Tmp "&M018_Tmp.";
*/


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



/*** CODEGEN FROM TARGET METADATA ***/
%macro munge_monthly_mssp_assignment();

	%let pioneer_test =%sysfunc(cats(&cclf_ccr_absent_any_prior_cclf8.,&cclf_ccr_limit_to_assigned_only.));
	%put &=pioneer_test.;	

	%AssertThat(%upcase(&pioneer_test.)
		,ne
		,EXCLUDEFALSE
		,ReturnMessage=Pioneer client does not have assignment files.
		,FailAction=EndActiveSASSession
		)

	proc sql;
		create table table_1_full as
		select *
		from m017_out.table_1
		;
	quit;

	data table_1_reduced;
		set table_1_full;
		drop first_name last_name;
	run;

	proc sort
			data=table_1_reduced
			out=table_1_sort;
		by hicno date_start date_end;
	run;

	proc transpose
		data=table_1_sort
		out=table_1_long(
			rename=(_NAME_=elig_month_str COL1=elig_num)
			)
		;
	by hicno date_start date_end hassgn;
	var
		monthly_elig_1
		monthly_elig_2
		monthly_elig_3
		monthly_elig_4
		monthly_elig_5
		monthly_elig_6
		monthly_elig_7
		monthly_elig_8
		monthly_elig_9
		monthly_elig_10
		monthly_elig_11
		monthly_elig_12
		;
	run;

	data table_1_readable;
		set table_1_long;
		elig_month=SUBSTR(elig_month_str, ANYDIGIT(elig_month_str));
		length elig_status $13;
		if elig_num = 0 then do;
			elig_status = 'NO_ELIG';
		end;
		if elig_num eq 1 then do;
			elig_status = 'ESRD';
		end;
		if elig_num eq 2 then do;
			elig_status = 'Disabled';
		end;
		if elig_num eq 3 then do;
			elig_status = 'Aged Dual';
		end;
		if elig_num eq 4 then do;
			elig_status = 'Aged Non-Dual';
		end;
		drop elig_month_str elig_num;
	run;

	data table_1_values_only;
		set table_1_readable;
		if elig_status ne '' then output table_1_values_only;
	run;
		
	data elig_windows;
		set table_1_values_only;
		format date_elig_start yymmdd10. date_elig_end yymmdd10.;
		if hassgn eq 'PROSP' then do;
			date_elig_start = intnx('month',date_end,-24+elig_month);
			date_elig_end = intnx('month',date_end,-23+elig_month)-1;
		end;
		else do;
			date_elig_start = intnx('month',date_end,-12+elig_month);
			date_elig_end = intnx('month',date_end,-11+elig_month)-1;
		end;
		drop date_start date_end elig_month;
	run;


	/*Prioritize retrospective HASSGN over QASSGN. If there is a HASSGN we 
	don't want to keep the QASSGN for that year. Prioritize QASSGN over the
	prospective HASSGN as well*/
	
	/*Assign the appropriate priorities to the HASSGN and QASSGN*/
	data elig_windows_prioritized;
		set elig_windows;
		if hassgn = "TRUE" then do;
			priority = 1;
		end;
		else if hassgn = "FALSE" then do;
			priority = 2;
		end;
		else do;
			priority = 3;
		end;
	run;

	/*Get down to a unique list by month of HICNO with their highest priority assignment*/

	proc sort data=elig_windows_prioritized;
		by HICNO date_elig_end priority;
	run;

	data elig_windows_reduced (drop=priority);
		set elig_windows_prioritized;
		by HICNO date_elig_end;
		if first.date_elig_end then output elig_windows_reduced;
	run;

	/*Output eligibility data*/
	
	data M018_Tmp.monthly_elig_status;
		set elig_windows_reduced;
	run;
	%LabelDataSet(M018_Tmp.Monthly_Elig_Status)

%mend;

%put System Return Code = &syscc.;
