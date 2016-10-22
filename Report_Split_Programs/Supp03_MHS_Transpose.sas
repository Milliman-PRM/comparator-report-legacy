/*
### CODE OWNERS: Anna Chen, Jack Leemhuis
### OBJECTIVE:
	Create a Supp program that can transfer the client market split reference file from txt file to csv. This program is for MHS only. 

### DEVELOPER NOTES:
	

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/*Libnames*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Import the client market split reference file.*/
data Market_Splits_import (drop = MARKET_NAME_Orig where = (upcase(market_name) ne "MA"));
  	infile "&Path_Project_Received_Ref.\HICNO_MARKET_MSSP_2015Q3.txt" 
	lrecl = 1000 truncover dsd firstobs = 2;
 	input HICNO $11.
 	      MARKET_NAME_Orig $16.
		  ;
	format market_name $16.;

	market_name = propcase(MARKET_NAME_Orig);
run;

/*Transpose the data to the desired format.*/
proc sort data = Market_Splits_import out = Market_Splits_import_sorted;
	by market_name;
run;

data Market_Splits_group;
	set Market_Splits_import_sorted;
	by market_name;
		if first.market_name then count = 0;
		   count+1;
run;

proc sort data = Market_Splits_group out = Market_Splits_group_sorted;
	by count;
run;

proc transpose data = Market_Splits_group_sorted 
	out = Market_Splits_trans (drop = count _name_);
		by count;
		id market_name;
		var HICNO;
run;

/*Rename the columns so that they won't start with an underscore.*/
proc sql noprint;
	select catx('=',name,scan(name,-1,'_'))
	into : base separated by ' '
 	from dictionary.columns 
	where libname='WORK' and memname='MARKET_SPLITS_TRANS' and name like '_%';

quit;
%put &base;

proc datasets library=work nolist;
	modify Market_Splits_trans;
	rename &base;
quit;

/*Output the new table into csv format.*/
proc export data = Market_Splits_trans
	outfile= "&Path_Project_Received_Ref.\Market_Splits.csv"
	dbms=csv replace;
run;

%put System Return Code = &syscc.;
