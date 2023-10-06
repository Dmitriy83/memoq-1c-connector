#Region FormCommandsEventHandlers

&AtClient
Procedure Settings(Command)
	OpenForm("CommonForm.Constants");
EndProcedure

&AtClient
Procedure UploadFilesToMemoq(Command)
	OpenForm("DataProcessor.ImportExportFilesMemoQ.Form");
EndProcedure

#EndRegion