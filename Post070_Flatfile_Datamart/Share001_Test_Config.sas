/*
### CODE OWNERS: Jason Altieri, Aaron Burgess

### OBJECTIVE:
	Test if the code should be run based on client code.

### DEVELOPER NOTES:
	<none>
*/

/*Run these lines if testing interactively
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

data config;
	infile "%GetParentFolder(1)configuration\config_rules.csv"
	dsd
	firstobs=2
	;
	input
		client_abbreviation :$6.
		trigger :$42.
		;
run;

proc sql noprint;
	select
		sum(index(%upcase("&path_project_received."), strip(upcase(client_abbreviation))))
		into :client_indicator separated by ","
	from config
	where upcase(trigger) = "FLATFILE_DM"
	;
quit;

%put &=client_indicator.;

%AssertThat(%upcase(&client_indicator.)
	,gt
	,0
	,ReturnMessage=Only run for clients that request a flatfile datamart.
	,FailAction=EndActiveSASSession
	)

%put System Return Code = &syscc.;
