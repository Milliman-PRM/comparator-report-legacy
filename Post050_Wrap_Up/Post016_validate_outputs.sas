/*
### CODE OWNERS: Aaron Hoch, Kyle Baird, Shea Parkes, Michael Menser

### OBJECTIVE:
	Validate the outputs against the given data mart to ensure we are supplying
	data that meets specifications.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M002_cde.supp01_validation_functions.sas";

libname post050 "&post050.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



%ValidateAgainstTemplate(
	validate_libname=post050
	,validate_template=&name_datamart_target.
	)

Proc SQL NoPrint; 
	create table chk_output_tables as
	select
			libname 
			,memname
			,name
	from dictionary.columns
	where
		upcase(libname) eq "POST050"
	order by 
		memname
		,name 
	;
quit;

Proc SQL NoPrint;
	select count(distinct memname)
	into :cnt_output_tables trimmed
	from chk_output_tables 
	;
	select count(distinct memname)
	into :cnt_out_w_nameclient trimmed
	from chk_output_tables
	where upcase(name) eq "NAME_CLIENT"
	; 
quit;
%put cnt_output_tables = &cnt_output_tables.;
%put cnt_out_w_nameclient = &cnt_out_w_nameclient.;
%AssertThat(&cnt_output_tables.
			,eq
			,&cnt_out_w_nameclient.
			,ReturnMessage=It is not the case that all output tables contain name_client.
			)

Proc SQL NoPrint; 
	select
		catx("." 
			,libname 
			,memname 
		)
	into :codegen_tables_w_name_client separated by " "
	from chk_output_tables
	where upcase(name) eq "NAME_CLIENT"
	order by name 
	;
quit;

%put codegen_tables_w_name_client = &codegen_tables_w_name_client.;

data Name_client_All;
	set &codegen_tables_w_name_client.;
	keep name_client; 
run;

proc sql; 
	create table Name_client_Unique as
	select distinct name_client
	from Name_client_All
	order by name_client
	;
quit;

data additional_client_names;
	set Name_client_Unique;
	where upcase(name_client) ne upcase("&name_client.");
run;

%AssertDataSetNotPopulated(additional_client_names)

proc sql;
	create table metric_id_all_values as
	select distinct metric_id
	from post050.metrics_key_value
	;
quit;

data invalid_metric_id_values (WHERE = (validity = 0));
	set metric_id_all_values;
	validity = nvalid(metric_id, 'v7');
run;

%AssertDataSetNotPopulated(DataSetName = invalid_metric_id_values, 
                           ReturnMessage = At least one of the metric id variables does not follow the conventions of SAS.);

%put System Return Code = &syscc.;
