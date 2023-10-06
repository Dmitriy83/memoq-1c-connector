//@skip-check use-non-recommended-method
		
#If Server Or ThickClientOrdinaryApplication Or ExternalConnection Then

#Region Public

// Upload to MemoQ.
// 
// Parameters:
//  SourceFolderPath 	- String 			- Source folder path
//  ProjectName 		- String 			- Project name
//  DirectoriesFilter 	- Array of String 	- Directories filter
// 
// Returns:
//  String -  Project name
//
Function UploadToMemoQ(SourceFolderPath, ProjectName, DirectoriesFilter) Export
	
	StartTime = CurrentSessionDate();
	
	// First of all, let's find project by name
	ProjectGuid = GetProjectGuid(ProjectName, Constants.CreateNewProjectIfNotFound.Get()); 
	If Not ValueIsFilled(ProjectGuid) Then
		Return "";
	EndIf; 	
	
	Files = FindFiles(SourceFolderPath, "*.lstr", True);
	For Each File In Files Do
		
		If DirectoriesFilter.Count() > 0 And DirectoriesFilter.Find(Left(File.Path, StrLen(File.Path) - 1)) = Undefined Then
			Continue;
		EndIf;
		
		// We can't use WSReferences or WSProxy to work with object model of wsdl, because we have to fill in Header in the SOAP message and 1C:Platform can't do it.
		
		// Begin uploading
		Response = SendSOAPMessage(MessageText_BeginChunkedFileUpload(File.FullName), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/BeginChunkedFileUpload");
		FileGuid = ConvertStringToXDTO(Response, "XDTO").Body.BeginChunkedFileUploadResponse.BeginChunkedFileUploadResult;
		
		// Add file chunks	
		FileStream = New FileStream(File.FullName, FileOpenMode.Open, FileAccess.Read);
		DataReader = New DataReader(FileStream); 
		FileParts = DataReader.SplitInPartsOf(GetFileChunkSize());
		For Each FilePart In FileParts Do
			Response = SendSOAPMessage(MessageText_AddNextFileChunk(FileGuid, Base64String(FilePart.GetBinaryData())), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/AddNextFileChunk");
		EndDo;
		FileStream.Close();
		
		// Close uploading
		Response = SendSOAPMessage(MessageText_EndChunkedFileUpload(FileGuid), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/EndChunkedFileUpload");
			
		// Import file to the project
		Response = SendSOAPMessage(MessageText_ImportTranslationDocumentsWithOptions(FileGuid, ProjectGuid, GetPathToSetAsImportPathWithFileName(File, SourceFolderPath)), "ServerProject/ServerProjectService", "http://kilgray.com/memoqservices/2007/IServerProjectService/ImportTranslationDocumentsWithOptions");
		
		// Delete file
		Response = SendSOAPMessage(MessageText_DeleteFile(FileGuid), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/DeleteFile");

	EndDo;
	
	Message(StrTemplate(NStr("en = 'Success. Process time %1 sec.';"), CurrentSessionDate() - StartTime));
	
	// Get exact project name, for future downloading
    Response = SendSOAPMessage(MessageText_GetProject(ProjectGuid), "ServerProject/ServerProjectService", "http://kilgray.com/memoqservices/2007/IServerProjectService/GetProject");
	ResponseXDTO = ConvertStringToXDTO(Response, "XDTO");
	Return ResponseXDTO.Body.GetProjectResponse.GetProjectResult.Name;
	
EndFunction

// Download from MemoQ.
// 
// Parameters:
//  TargetFolderPath 	- String - Target folder path
//  ProjectName 		- String - Project name
//
Procedure DownloadFromMemoQ(TargetFolderPath, ProjectName) Export
	
	StartTime = CurrentSessionDate();
	
	// First of all, let's find project by name
	ProjectGuid = GetProjectGuid(ProjectName); 
	If Not ValueIsFilled(ProjectGuid) Then
		Return;
	EndIf;
	
	// Get files list from project  
	For Each TranslatedFile In GetTranslatedFiles(ProjectGuid) Do 
		// Export
		Response = SendSOAPMessage(MessageText_ExportTranslationDocument(ProjectGuid, TranslatedFile.DocumentGuid), "ServerProject/ServerProjectService", "http://kilgray.com/memoqservices/2007/IServerProjectService/ExportTranslationDocument");
		ResponseXDTO = ConvertStringToXDTO(Response, "XDTO");
		FileGuid = ResponseXDTO.Body.ExportTranslationDocumentResponse.ExportTranslationDocumentResult.FileGuid;
		
		// Begin downloading
		Response = SendSOAPMessage(MessageText_BeginChunkedFileDownload(FileGuid), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/BeginChunkedFileDownload");
		ResponseXDTO = ConvertStringToXDTO(Response, "XDTO");
		SessionId = ResponseXDTO.Body.BeginChunkedFileDownloadResponse.BeginChunkedFileDownloadResult;
		FileSize = Number(ResponseXDTO.Body.BeginChunkedFileDownloadResponse.FileSize);
		
		// Get file chunks
		TargetFileFullName = GetTargetFileFullName(TargetFolderPath, TranslatedFile);		
		TargetFileDirectory = New File(GetFileDirectory(TargetFileFullName));		
		If Not TargetFileDirectory.Exists() Then
			// Create folder
			CreateDirectory(TargetFileDirectory.FullName);
		EndIf;
		FileStream = New FileStream(TargetFileFullName, FileOpenMode.Create, FileAccess.Write);
		DataWriter = New DataWriter(FileStream);		
		
		FileChunkSize = Min(FileSize, GetFileChunkSize());
		FileSizeRemainder = FileSize;
		While FileSizeRemainder > 0 Do 		
			Response = SendSOAPMessage(MessageText_GetNextFileChunk(SessionId, FileChunkSize), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/GetNextFileChunk");
			ResponseXDTO = ConvertStringToXDTO(Response, "XDTO");
			Value = ResponseXDTO.Body.GetNextFileChunkResponse.GetNextFileChunkResult;
			DataWriter.Write(Base64Value(Value));
			
			FileSizeRemainder = FileSizeRemainder - FileChunkSize;
		EndDo; 
		
		FileStream.Close();
		
		// Close downloading
		Response = SendSOAPMessage(MessageText_EndChunkedFileDownload(SessionId), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/EndChunkedFileDownload");
		
		// Delete file 
		Response = SendSOAPMessage(MessageText_DeleteFile(FileGuid), "FileManager/FileManagerService", "http://kilgray.com/memoqservices/2007/IFileManagerService/DeleteFile");
	EndDo; 	
	
	Message(StrTemplate(NStr("en = 'Success. Process time %1 sec.';"), CurrentSessionDate() - StartTime));
	
EndProcedure

#EndRegion

#Region Private

Function GetProjectGuid(ProjectName, CreateNewProjectIfNotFound = False)

	Response = SendSOAPMessage(MessageText_ListProjects(ProjectName), "ServerProject/ServerProjectService", "http://kilgray.com/memoqservices/2007/IServerProjectService/ListProjects");
	Cancel = False;
	ServerProjectInfo = GetServerProjectInfo(ConvertStringToXDTO(Response, "XDTO"), Cancel, ProjectName);
	If Cancel Then
		Return Undefined;
	EndIf;
	If CreateNewProjectIfNotFound And ServerProjectInfo = Undefined Then
		// Get project template Id
		Response = SendSOAPMessage(MessageText_ListProjectTemplates(ProjectName), "Resource/ResourceService", "http://kilgray.com/memoqservices/2007/IResourceService/ListResources");
		Cancel = False;
		ProjectTemplateInfo = GetProjectTemplateInfo(ConvertStringToXDTO(Response, "XDTO"), Cancel);
		If Cancel Then
			Return Undefined;
		EndIf;
		ProjectTemplateGuid = ProjectTemplateInfo.Guid;
		
		// Create new project 		
		Response = SendSOAPMessage(MessageText_CreateProjectFromTemplate(ProjectTemplateGuid), "ServerProject/ServerProjectService", "http://kilgray.com/memoqservices/2007/IServerProjectService/CreateProjectFromTemplate");
		ResponseXDTO = ConvertStringToXDTO(Response, "XDTO");
		Return ResponseXDTO.Body.CreateProjectFromTemplateResponse.CreateProjectFromTemplateResult.ProjectGuid;
	Else
		Return ServerProjectInfo.ServerProjectGuid;
	EndIf; 
	
EndFunction  

Function GetTranslatedFiles(ProjectGuid)
	
	Response = SendSOAPMessage(MessageText_ListProjectTranslationDocuments(ProjectGuid), "ServerProject/ServerProjectService", "http://kilgray.com/memoqservices/2007/IServerProjectService/ListProjectTranslationDocuments");
	ResponseXDTO = ConvertStringToXDTO(Response, "XDTO");
	If ResponseXDTO.Body.ListProjectTranslationDocumentsResponse.ListProjectTranslationDocumentsResult.Properties().Count() = 0 Then
		Return New Array;	
	EndIf;
	If TypeOf(ResponseXDTO.Body.ListProjectTranslationDocumentsResponse.ListProjectTranslationDocumentsResult.ServerProjectTranslationDocInfo) <> Type("XDTOList") Then 
		Result = New Array;
		Result.Add(ResponseXDTO.Body.ListProjectTranslationDocumentsResponse.ListProjectTranslationDocumentsResult.ServerProjectTranslationDocInfo);
		Return Result;		
	Else
		Return ResponseXDTO.Body.ListProjectTranslationDocumentsResponse.ListProjectTranslationDocumentsResult.ServerProjectTranslationDocInfo;
	EndIf; 
		
EndFunction

Function ConvertStringToXDTO(Value, Type)
	If Not ValueIsFilled(Value) Then 
		Return Undefined;	
	EndIf;
	If StrFind(Type, "XDTO") > 0 Then
		Reader = New XMLReader;
    	Reader.SetString(Value);
		Return XDTOFactory.ReadXML(Reader);
	Else
		Return XMLString(Value);
	EndIf;
КонецФункции

Function SendSOAPMessage(MessageText, ServiceName, SOAPAction)
	
	Try
		Headers = New Map; 
		Headers.Insert("Content-Type", 	"text/xml;charset=UTF-8");
		Headers.Insert("SOAPAction", 	SOAPAction);
		
		Connection = New HTTPConnection("antares.memoq.com", 9091,,,,, New OpenSSLSecureConnection, False); // Host has to be without https:// 	
		Request = New HTTPRequest("/zhiharevtest2/memoqservices/" + ServiceName, Headers); 
		Request.SetBodyFromString(MessageText);
		Response = Connection.CallHTTPMethod("POST", Request);				
		Возврат Response.GetBodyAsString();
	Except 
		Message(ErrorDescription());
	    Возврат Undefined;
	EndTry;
	
EndFunction

Function GetPathToSetAsImportPathWithFileName(File, Val SourceFolderPath) 
	Position = StrFind(SourceFolderPath, "\", SearchDirection.FromEnd, StrLen(SourceFolderPath) - 1);
	Return Right(File.FullName, StrLen(File.FullName) - Position);
EndFunction

Function GetFileChunkSize()
	FileChunkSize = Constants.FileChunkSize.Get();
	Return ?(ValueIsFilled(FileChunkSize), FileChunkSize, 524288);  // By default 0,5 MB
EndFunction

Function GetServerProjectInfo(ResponseXDTO, Cancel, ProjectName) 
	// The search is carried out not by exact match, but by substring matching. Therefore there may be a case of returning an array of elements.
	ProjectNotFoundMessage = NStr("en = 'Project was not found.';"); 
	CreateNewProjectIfNotFound = Constants.CreateNewProjectIfNotFound.Get();   
	If ResponseXDTO = Undefined Then
		Message(ProjectNotFoundMessage);
		Cancel = Not CreateNewProjectIfNotFound;
		Return Undefined;	
	EndIf;
	
	If ResponseXDTO.Body.ListProjectsResponse.ListProjectsResult.Properties().Count() = 0 Then
		Message(ProjectNotFoundMessage);
		Cancel = Not CreateNewProjectIfNotFound;
		Return Undefined;	
	EndIf;
	If TypeOf(ResponseXDTO.Body.ListProjectsResponse.ListProjectsResult.ServerProjectInfo) = Type("XDTOList") Then 
		If ResponseXDTO.Body.ListProjectsResponse.ListProjectsResult.ServerProjectInfo.Count() > 1 Then
			Message(NStr("en = 'It was found more than one project by the name.';"));
			Cancel = Not CreateNewProjectIfNotFound;
			Return Undefined;
		ElsIf ResponseXDTO.Body.ListProjectsResponse.ListProjectsResult.ServerProjectInfo.Count() = 0 Then
			Message(ProjectNotFoundMessage); 
			Cancel = Not CreateNewProjectIfNotFound;
			Return Undefined;
		EndIf;
		ServerProjectInfo = ResponseXDTO.Body.ListProjectsResponse.ListProjectsResult.ServerProjectInfo[0];		
	Else
		ServerProjectInfo = ResponseXDTO.Body.ListProjectsResponse.ListProjectsResult.ServerProjectInfo;
	EndIf; 
	
	If CreateNewProjectIfNotFound And ServerProjectInfo.Name <> ProjectName Then // Check on exact match
		Return Undefined;	
	EndIf;
	
	Return ServerProjectInfo;
EndFunction 

Function GetProjectTemplateInfo(ResponseXDTO, Cancel)
	// The search is carried out not by exact match, but by substring matching. Therefore there may be a case of returning an array of elements.
	ProjectTemplateNotFoundMessage = NStr("en = 'Project template was not found.';"); 
	If ResponseXDTO.Body.ListResourcesResponse.ListResourcesResult.Properties().Count() = 0 Then
		Message(ProjectTemplateNotFoundMessage);
		Cancel = True;
		Return Undefined;	
	EndIf;
	If TypeOf(ResponseXDTO.Body.ListResourcesResponse.ListResourcesResult.LightResourceInfo) = Type("XDTOList") Then 
		If ResponseXDTO.Body.ListResourcesResponse.ListResourcesResult.LightResourceInfo.Count() > 1 Then
			Message(NStr("en = 'It was found more than one project template by the name. Please set the project template name more precisely.';"));
			Cancel = True;
			Return Undefined;
		ElsIf ResponseXDTO.Body.ListResourcesResponse.ListResourcesResult.LightResourceInfo.Count() = 0 Then
			Message(ProjectTemplateNotFoundMessage); 
			Cancel = True;
			Return Undefined;
		EndIf;
		Return ResponseXDTO.Body.ListResourcesResponse.ListResourcesResult.LightResourceInfo[0];		
	Else
		Return ResponseXDTO.Body.ListResourcesResponse.ListResourcesResult.LightResourceInfo;
	EndIf;
EndFunction

Function GetTargetFileFullName(Val TargetFolderPath, TranslatedFile)
	If Right(TargetFolderPath, 1) <> "\" Then
		TargetFolderPath = TargetFolderPath + "\";	
	EndIf;
	ImportPath = TranslatedFile.ImportPath; 
	
	DiskSymbolPosition = StrFind(ImportPath, ":\"); 
	If DiskSymbolPosition <> 0 Then 
		ImportPath = Right(ImportPath, StrLen(ImportPath) - DiskSymbolPosition - 1);	
	EndIf; 
	
	If Left(ImportPath, 1) = "\" Then
		ImportPath = Right(ImportPath, StrLen(ImportPath) - 1);	
	EndIf;
	Return TargetFolderPath + ImportPath;	
EndFunction  

Function GetFileDirectory(Val FileFullName)
	File = New File(FileFullName);
	Return File.Path;	
EndFunction

#Region MessageTexts

Function MessageText_BeginChunkedFileUpload(FileName)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:BeginChunkedFileUpload>
	|         <ns:fileName>&FileName</ns:fileName>
	|         <ns:isZipped>false</ns:isZipped>
	|      </ns:BeginChunkedFileUpload>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get()); 
	MessageText = StrReplace(MessageText, "&FileName", 	FileName);
	Return MessageText;
EndFunction  

Function MessageText_AddNextFileChunk(FileGuid, FileData)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:AddNextFileChunk>
	|         <ns:fileIdAndSessionId>&FileGuid</ns:fileIdAndSessionId>
	|         <ns:fileData>&FileData</ns:fileData>
	|      </ns:AddNextFileChunk>
	|   </soapenv:Body>
	|</soapenv:Envelope>";      
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&FileGuid", 	FileGuid); 
	MessageText = StrReplace(MessageText, "&FileData", 	FileData);
	Return MessageText;
EndFunction 

Function MessageText_EndChunkedFileUpload(FileGuid)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:EndChunkedFileUpload>
	|         <ns:fileIdAndSessionId>&FileGuid</ns:fileIdAndSessionId>
	|      </ns:EndChunkedFileUpload>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&FileGuid", 	FileGuid);
	Return MessageText;
EndFunction 

Function MessageText_DeleteFile(FileGuid)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:DeleteFile>
	|         <ns:fileGuid>&FileGuid</ns:fileGuid>
	|      </ns:DeleteFile>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&FileGuid", 	FileGuid);
	Return MessageText;
EndFunction 

Function MessageText_ImportTranslationDocumentsWithOptions(FileGuid, ProjectGuid, PathToSetAsImportPath)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"" xmlns:arr=""http://schemas.microsoft.com/2003/10/Serialization/Arrays"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:ImportTranslationDocumentsWithOptions>
	|		<ns:serverProjectGuid>&ProjectGuid</ns:serverProjectGuid>         
	|         <ns:importDocOptions>
	|            <ns:ImportTranslationDocumentOptions>
	|               <ns:FileGuid>&FileGuid</ns:FileGuid>  
	|
	|               <!--FilterConfigResGuid we can get from /memoqservices/resource/ListResources--> 
	|               <ns:FilterConfigResGuid>&FilterConfigResGuid</ns:FilterConfigResGuid>
	|               
	|               <ns:ImportEmbeddedImages>false</ns:ImportEmbeddedImages>
	|               <ns:ImportEmbeddedObjects>true</ns:ImportEmbeddedObjects>
	|               
	|               <ns:PathToSetAsImportPath>&PathToSetAsImportPath</ns:PathToSetAsImportPath>
	|               
	|               <ns:TargetLangCodes>
	|                  <arr:string>rum</arr:string>
	|               </ns:TargetLangCodes>
	|            </ns:ImportTranslationDocumentOptions>
	|         </ns:importDocOptions>
	|      </ns:ImportTranslationDocumentsWithOptions>
	|   </soapenv:Body>
	|</soapenv:Envelope>";      
	MessageText = StrReplace(MessageText, "&ApiKey", 				Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&FileGuid", 				FileGuid); 
	MessageText = StrReplace(MessageText, "&ProjectGuid", 			ProjectGuid);
	MessageText = StrReplace(MessageText, "&PathToSetAsImportPath", PathToSetAsImportPath); 
	MessageText = StrReplace(MessageText, "&FilterConfigResGuid", 	Constants.FilterConfigResGuid.Get());
	Return MessageText;
EndFunction

Function MessageText_ListProjects(ProjectName)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header>
	|   	 <ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:ListProjects>
	|		  <ns:filter>
	|            <ns:NameOrDescription>&ProjectName</ns:NameOrDescription>            
	|         </ns:filter>
	|      </ns:ListProjects>
	|   </soapenv:Body>
	|</soapenv:Envelope>";      
	MessageText = StrReplace(MessageText, "&ApiKey", 		Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&ProjectName", 	ProjectName);
	Return MessageText;
EndFunction  

Function MessageText_ListProjectTemplates(ProjectTemplateName)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:ListResources>
	|         <ns:resourceType>ProjectTemplate</ns:resourceType>
	|         <ns:filter>
	|            <ns:NameOrDescription>&ProjectTemplateName</ns:NameOrDescription>
	|         </ns:filter>
	|      </ns:ListResources>
	|   </soapenv:Body>
	|</soapenv:Envelope>";      
	MessageText = StrReplace(MessageText, "&ApiKey", 				Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&ProjectTemplateName", 	ProjectTemplateName);
	Return MessageText;
EndFunction 

Function MessageText_CreateProjectFromTemplate(ProjectTemplateGuid)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"" xmlns:arr=""http://schemas.microsoft.com/2003/10/Serialization/Arrays"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:CreateProjectFromTemplate>
	|         <ns:createInfo>
	|            <ns:CreatorUser>00000000-0000-0000-0001-000000000001</ns:CreatorUser>
	|            <ns:TemplateGuid>&ProjectTemplateGuid</ns:TemplateGuid>
	|         </ns:createInfo>
	|      </ns:CreateProjectFromTemplate>
	|   </soapenv:Body>
	|</soapenv:Envelope>";      
	MessageText = StrReplace(MessageText, "&ApiKey", 				Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&ProjectTemplateGuid", 	ProjectTemplateGuid);
	Return MessageText;
EndFunction 

Function MessageText_ListProjectTranslationDocuments(ProjectGuid)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:ListProjectTranslationDocuments>         
	|         <ns:serverProjectGuid>&ProjectGuid</ns:serverProjectGuid>
	|      </ns:ListProjectTranslationDocuments>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get()); 
	MessageText = StrReplace(MessageText, "&ProjectGuid", 	ProjectGuid);
	Return MessageText;
EndFunction

Function MessageText_BeginChunkedFileDownload(FileGuid)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:BeginChunkedFileDownload>
	|         <ns:fileGuid>&FileGuid</ns:fileGuid>
	|         <ns:zip>false</ns:zip>
	|      </ns:BeginChunkedFileDownload>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get()); 
	MessageText = StrReplace(MessageText, "&FileGuid", 	FileGuid);
	Return MessageText;
EndFunction 

Function MessageText_EndChunkedFileDownload(SessionId)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:EndChunkedFileDownload>
	|         <ns:sessionId>&SessionId</ns:sessionId>
	|      </ns:EndChunkedFileDownload>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 	Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&SessionId", SessionId);
	Return MessageText;
EndFunction 

Function MessageText_GetNextFileChunk(SessionId, FileChunkSize)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:GetNextFileChunk>
	|         <ns:sessionId>&SessionId</ns:sessionId>
	|         <ns:byteCount>&FileChunkSize</ns:byteCount>
	|      </ns:GetNextFileChunk>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 		Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&SessionId", 	SessionId);
	MessageText = StrReplace(MessageText, "&FileChunkSize", Format(FileChunkSize, "NG=0"));
	Return MessageText;
EndFunction 

Function MessageText_ExportTranslationDocument(ProjectGuid, DocumentGuid) 
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header><ApiKey>&ApiKey</ApiKey></soapenv:Header>
	|   <soapenv:Body>
	|      <ns:ExportTranslationDocument>
	|         <ns:serverProjectGuid>&ProjectGuid</ns:serverProjectGuid>         
	|         <ns:docGuid>&DocumentGuid</ns:docGuid>
	|      </ns:ExportTranslationDocument>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 		Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&ProjectGuid", 	ProjectGuid);
	MessageText = StrReplace(MessageText, "&DocumentGuid", 	DocumentGuid);
	Return MessageText;
EndFunction

Function MessageText_GetProject(ProjectGuid)
	MessageText =
	"<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:ns=""http://kilgray.com/memoqservices/2007"">
	|   <soapenv:Header>
	|   	 <ApiKey>&ApiKey</ApiKey>
	|   </soapenv:Header>
	|   <soapenv:Body>
	|      <ns:GetProject>
	|         <ns:spGuid>&ProjectGuid</ns:spGuid>
	|      </ns:GetProject>
	|   </soapenv:Body>
	|</soapenv:Envelope>"; 
	MessageText = StrReplace(MessageText, "&ApiKey", 		Constants.MemoqApiKey.Get());
	MessageText = StrReplace(MessageText, "&ProjectGuid", 	ProjectGuid);
	Return MessageText;
EndFunction

#EndRegion

#EndRegion

#Else
Raise NStr("en = 'Invalid object call on the client.';");
#EndIf