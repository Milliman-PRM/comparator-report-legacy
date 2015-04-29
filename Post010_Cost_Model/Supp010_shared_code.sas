/*
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
	Store code that is shared across multiple programs in the module
	to help lessen duplication.

### DEVELOPER NOTES:
	<none>
*/
%let name_datamart_target = cost_model;
%let name_module = Post010_Cost_Model;

%let path_dir_outputs = &path_project_data.postboarding\&name_module.\;
%put path_dir_outputs = &path_dir_outputs.;
%CreateFolder(&path_dir_outputs.)

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/






%put System Return Code = &syscc.;
