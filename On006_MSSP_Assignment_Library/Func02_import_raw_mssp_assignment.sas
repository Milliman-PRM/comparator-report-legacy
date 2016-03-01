/*
### CODE OWNERS: Shea Parkes, Kyle Baird, Jason Altieri, Jack Leemhuis

### OBJECTIVE:
	Bring raw assignment information into SAS.

### DEVELOPER NOTES:
	This could likely be replaced with a codegen step in Python.
*/

/*	Run these lines if testing interactively
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
libname M017_Out "&M017_Out.";
*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


%macro Import_Raw_Assignment(lib_out);

	%let pioneer_test =%sysfunc(cats(&cclf_ccr_absent_any_prior_cclf8.,&cclf_ccr_limit_to_assigned_only.));
	%put &=pioneer_test.;	

	%AssertThat(%upcase(&pioneer_test.)
		,ne
		,EXCLUDEFALSE
		,ReturnMessage=Pioneer client does not have assignment files.
		,FailAction=EndActiveSASSession
		)

	data &lib_out..table_1;
		infile
			"&M017_Out.table_1.csv"
			dsd
			delimiter = ","
			firstobs = 2
			truncover
			lrecl = 32767
			;
		input
			date_start :MMDDYY10.
			date_end :MMDDYY10.
			hicno :$11.
			first_name :$40.
			last_name :$40.
			hassgn :$5.
			;
		format date_: YYMMDDd10.;
	run;

	%LabelDataSet(&lib_out..table_1)

	data &lib_out..table_2;
		infile
			"&M017_Out.table_2.csv"
			dsd
			delimiter = ","
			firstobs = 2
			truncover
			lrecl = 32767
			;
		input
			date_start :MMDDYY10.
			date_end :MMDDYY10.
			hicno :$11.
			first_name :$40.
			last_name :$40.
			TIN :$10.
			hassgn :$5.
			;
		format date_: YYMMDDd10.;
	run;

	%LabelDataSet(&lib_out..table_2)

	data &lib_out..table_3;
		infile
			"&M017_Out.table_3.csv"
			dsd
			delimiter = ","
			firstobs = 2
			truncover
			lrecl = 32767
			;
		input
			date_start :MMDDYY10.
			date_end :MMDDYY10.
			hicno :$11.
			first_name :$40.
			last_name :$40.
			CCN :$6.
			hassgn :$5.
			;
		format date_: YYMMDDd10.;
	run;

	%LabelDataSet(&lib_out..table_3)

	data &lib_out..table_4;
		infile
			"&M017_Out.table_4.csv"
			dsd
			delimiter = ","
			firstobs = 2
			truncover
			lrecl = 32767
			;
		input
			date_start :MMDDYY10.
			date_end :MMDDYY10.
			hicno :$11.
			first_name :$40.
			last_name :$40.
			TIN :$10.
			NPI :$10.
			hassgn :$5.
			;
		format date_: YYMMDDd10.;
	run;

	%LabelDataSet(&lib_out..table_4)

%mend;

%put System Return Code = &syscc.;
