/*
### CODE OWNERS: Sarah Prusinski

### OBJECTIVE:
	Create a Supp program that can be ran after the general process to create all of the files but split into client provided groups.

### DEVELOPER NOTES:
	

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

proc import datafile = "\\indy-syn01.milliman.com\prm_phi\PHI\0273NYP\NewYorkMillimanShare\Market Level Reporting\INOVA\A2530_MSSP_Att&Markets_2Q2015.xlsx"
	out = splits
	dbms = xlsx
	replace;
run;

data Market_A (keep = Market_A_InovaRegion rename = (Market_A_InovaRegion = Member_id))
	 Market_B (keep = Market_B_InovaTINs rename = (Market_B_InovaTINs = Member_id))
	 Market_C (keep = Market_C_HCIPA rename = (Market_C_HCIPA = Member_id))
	 Market_D (keep = Market_D_ValleyRegion rename = (Market_D_ValleyRegion = Member_id))
	 Market_E (keep = Market_E_VPE rename = (Market_E_VPE = Member_id));
	set splits;

	if Market_A_InovaRegion ne "" then do;
		label Market_A_InovaRegion = Member_id;
		output Market_A;
	end;

	if Market_B_InovaTINs ne "" then do;
		label Market_B_InovaTINs = Member_id;
		output Market_B;
	end;

	if Market_C_HCIPA ne "" then do;
		label Market_C_HCIPA = Member_id;
		output Market_C;
	end;

	if Market_D_ValleyRegion ne "" then do;
		label Market_D_ValleyRegion = Member_id;
		output Market_D;
	end;

	if Market_E_VPE ne "" then do;
		label Market_E_VPE = Member_id;
		output Market_E;
	end;

run;




