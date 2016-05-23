#Release Notes

## v5.1.1
  - Re-instated the `Path()` call in Wrap-Up so the resulting object would `Path` object as expected by the program

####Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- *none*

###Logic Changes
- Updated Pioneer logic to create client member time based on the presence of claims in a given year

###Lower Level Changes
- Derive the most recent Beneficiary Exclusion file
- Fixed the market split naming code to only append the current market name
- Update to new python parser


##v5.0.0

####Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- *none*

####Logic Changes
- Use component MARA risk scores (this will not impact NYP)

####Lower Level Changes
- Updated postboarding datamart creation script to be compatible with analytics-pipeline v5.11
