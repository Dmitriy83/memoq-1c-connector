#Region FormEventHandlers

&AtClient
Procedure OnOpen(Cancel)
	FillDirectoriesTree(); 
	SetItemsVisibility();
EndProcedure  

#EndRegion

#Region FormHeaderItemsEventHandlers

&AtClient
Async Procedure SourceFolderPathStartChoice(Item, ChoiceData, StandardProcessing)
	OpenFileDialog = New FileDialog(FileDialogMode.ChooseDirectory);
	OpenFileDialog.FullFileName 	= Object.SourceFolderPath;
	OpenFileDialog.Title 			= NStr("en = 'Select path to the source folder'");
	//@skip-check unknown-method-property
	ChoosenFiles = Await OpenFileDialog.ChooseAsync();
	If ChoosenFiles <> Undefined And ChoosenFiles.Count() > 0 Then  
		Object.SourceFolderPath = TrimAll(ChoosenFiles[0]);		
		FillDirectoriesTree();
	Else
	    DoMessageBoxAsync(NStr("en = 'Source folder not selected.'"));
	EndIf;
EndProcedure

&AtClient
Async Procedure TargetFolderPathStartChoice(Item, ChoiceData, StandardProcessing)
	OpenFileDialog = New FileDialog(FileDialogMode.ChooseDirectory);
	OpenFileDialog.FullFileName 	= Object.TargetFolderPath;
	OpenFileDialog.Title 			= NStr("en = 'Select path to the target folder'");
	//@skip-check unknown-method-property
	ChoosenFiles = Await OpenFileDialog.ChooseAsync();
	If ChoosenFiles <> Undefined And ChoosenFiles.Count() > 0 Then  
		Object.TargetFolderPath = ChoosenFiles[0];	    
	Else
	    DoMessageBoxAsync(NStr("en = 'Target folder not selected.'"));
	EndIf;
EndProcedure

&AtClient
Procedure SourceFolderPathOnChange(Item)
	Object.SourceFolderPath = TrimAll(Object.SourceFolderPath);
	FillDirectoriesTree();
EndProcedure  

&AtClient
Procedure UploadAllFilesOnChange(Item)
	SetItemsVisibility();
EndProcedure

#EndRegion

#Region FormTableItemsEventHandlersDirectoriesTree

&AtClient
Procedure DirectoriesTreeMarkOnChange(Item)
	CurrentData = Items.DirectoriesTree.CurrentData;
	// Mark subordinate rows 
	SetChecked(CurrentData, CurrentData.Mark); 
EndProcedure 

#EndRegion

#Region FormCommandsEventHandlers 

&AtClient
Procedure Upload(Command) 
	UploadAtServer();
EndProcedure

&AtClient
Procedure Download(Command)
	DownloadAtServer();
EndProcedure

&AtClient
Procedure CheckAll(Command)
	SetChecked(DirectoriesTree, True);
EndProcedure

&AtClient
Procedure UncheckAll(Command)
	SetChecked(DirectoriesTree, False)
EndProcedure

#EndRegion

#Region Private 

&AtServer
Procedure UploadAtServer()    
	ProjectName = FormAttributeToValue("Object").UploadToMemoQ(Object.SourceFolderPath, Object.ApplictionName, GetDirectoriesFilter());
	If ValueIsFilled(ProjectName) Then
		Object.ProjectName = ProjectName;	
	EndIf;
EndProcedure

&AtServer
Procedure DownloadAtServer()
	FormAttributeToValue("Object").DownloadFromMemoQ(Object.TargetFolderPath, Object.ProjectName);
EndProcedure

&AtServer
Procedure FillDirectoriesTree()
	ClearDirectoriesTree();
	If Not ValueIsFilled(Object.SourceFolderPath) Then
		Return;	
	EndIf;
	
	Tree = FormAttributeToValue("DirectoriesTree");
	
	ParentRows = New Map;
	Files = FindFiles(Object.SourceFolderPath, "*", True);  
	For Each File In Files Do
		If Not File.IsDirectory() Then
			Continue;
		EndIf;
		
		ParentRow = ParentRows.Get(Left(File.Path, StrLen(File.Path) - 1));
		If ParentRow = Undefined Then
			Row = Tree.Rows.Add();			
		Else
			Row = ParentRow.Rows.Add();				
		EndIf; 
		Row.Mark 		= True;
		Row.Directory 	= File.Name;
		Row.FullPath 	= File.FullName;
		ParentRows.Insert(File.FullName, Row);
	EndDo;
	
	ValueToFormAttribute(Tree, "DirectoriesTree");
EndProcedure 

&AtServer
Procedure ClearDirectoriesTree()
	Tree = FormAttributeToValue("DirectoriesTree");
	Tree.Rows.Clear();
	ValueToFormAttribute(Tree, "DirectoriesTree");
EndProcedure  

&AtClient
Procedure SetChecked(ParentItem, Checked = False)
	
	For Each Branch In ParentItem.GetItems() Do 
		Branch.Mark = Checked;
		SetChecked(Branch, Checked); 	
	EndDo;
	
EndProcedure  

&AtServer
Procedure SetItemsVisibility()
	Items.DirectoriesTree.Enabled = Not Object.UploadAllFiles;	
EndProcedure 

&AtServer
Function GetDirectoriesFilter() 
	DirectoriesFilter = New Array;	
	If Object.UploadAllFiles Then
		Return DirectoriesFilter;
	EndIf;
	
	Tree = FormAttributeToValue("DirectoriesTree");
	FillDirectoriesFilter(DirectoriesFilter, Tree);	
	Return DirectoriesFilter;
EndFunction

&AtServer
Procedure FillDirectoriesFilter(DirectoriesFilter, ParentRow)
	For Each Row In ParentRow.Rows Do
		If Row.Mark Then
			DirectoriesFilter.Add(Row.FullPath);	
		EndIf;
		FillDirectoriesFilter(DirectoriesFilter, Row);
	EndDo;	
EndProcedure

#EndRegion