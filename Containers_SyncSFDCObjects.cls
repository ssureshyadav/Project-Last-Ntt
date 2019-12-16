public Class Containers_SyncSFDCObjects
{
    public Class OrderWrapper
    {
        @auraEnabled 
        public Order orderRecord {get;set;}
        @auraEnabled 
        public List<OrderItem> orderLineRecords {get;set;}
    }
    
    @auraEnabled
    public static String fetchOrderStatus(Id recordId)
    {
        return [Select status from Order Where Id =:recordId].Status;
    }
    
    @auraEnabled
    public static List<String> fetchEnvironments()
    {
        List<String> lstEnvironments=new List<String>();
        for(Container_Environment__mdt env:[Select Id,DeveloperName from Container_Environment__mdt])
        {
            lstEnvironments.add(env.DeveloperName);
        }
        return lstEnvironments;
    }
    
    //Fetch Records
    @auraEnabled
    public static String fetchObjectInfo(Id recordId)
    {
        if(recordId.getSObjectType().getDescribe() == Schema.SobjectType.Account)
        {
            return fetchAccountInfo(recordId);
        }else if(recordId.getSObjectType().getDescribe() == Schema.SobjectType.Product2 ) //|| recordId.getSObjectType().getDescribe() == Schema.SobjectType.Containers_Arcosa_Tank_Product__c
        {
            return fetchProductInfo(recordId);
        }else if(recordId.getSObjectType().getDescribe() == Schema.SobjectType.Order)
        {
            return fetchOrderInfo(recordId);
        }
        return null;
    }
    
    @auraEnabled
    public static String syncOrderObject(Id recordId)
    {
       /* Order orderInfo=[Select Id,OrderNumber,Containers_Taxable__c,PoDate,Type,Containers_Load_No__c,Containers_Customer_No__c,Containers_Customer_PO__c,
                            Containers_Schedule_Date__c,CreatedDate,Containers_Payment_Terms__c,Containers_WareHouse__c,Containers_Freight_Terms__c,MEX_FreightDollarAmount__c,
                            Ship_To_Name__c,Containers_Ship_to__c,ShippingStreet,ShippingState,ShippingCity,ShippingCountry,ShippingpostalCode,Containers_Ship_Via__c 
                        FROM 
                            Order 
                        Where 
                            Id =: recordId]; */
       
        String body=Containers_GenerateBPCSOrder.generateOrderxml(recordId);
        System.debug('Body::::::::::::::::'+body);
        
        if(body.startsWith('Error:'))
        {
            return body;
        }
        String endpoint ='https://connect.trin.net/ws/soap/createBpcsOrder';
        //HttpResponse response=makeCallout(body,endpoint);
        Http h2 = new Http();
        HttpRequest req1 = new HttpRequest();
        req1.setHeader('Authorization','Basic '+EncodingUtil.base64Encode(Blob.valueOf('oraclecpq@trinityindustriesinc-HUUL4D' + ':' + 'f58e8a6d-2131-4764-8747-c4e1e302d74a')));
        req1.setHeader('Content-Type','text/xml');
        req1.setHeader('accept','text/xml');
        req1.setBody(body);
        req1.setMethod('POST');
        req1.setEndpoint(endpoint);
        HttpResponse response = h2.send(req1);
        System.debug(response.getBody());
        if(response.getStatusCode() == 200)
        {
            Order odr=new Order(Id=recordId);
            odr.RecordTypeId=Schema.sobjectType.Order.getRecordTypeInfosByDeveloperName().get('Containers_Order_Read_Only').getRecordTypeId();
            odr.Container_SyncedToBPCS__c =true;
            odr.Containers_Order_Status__c ='Sent to BPCS';
            odr.Containers_Submission__c = System.today();
            try{
            	update odr;
            }catch(Exception e)
            {
                System.debug(e.getMessage()+e.getStackTraceString());
                return e.getMessage()+e.getStackTraceString();
            }
            return 'Successfully File Created and SFTPed';
            
            
        }else{
            return  response.getBody();
        }
        
        //System.debug(response);
        //return null;
    }
    
    @auraEnabled
    public static String updateOrder(Id recordId)
    {
        Order order=[Select Id,OrderNumber,Containers_Confirmation_Sent_Date__c from Order Where Id = : recordId];
        Date confDate = order.Containers_Confirmation_Sent_Date__c;
        String response=Containers_SyncSFDCObjects.makeOrderCallout(order.OrderNumber,null,null);
        if(response =='No Data Found' || response.startsWith('Error:'))
        {
            if(response.contains('please try after 30 minutes') || response.contains('invalid'))
            {
                Order ord=new Order(Id=recordId);
                if(response.contains('please try after 30 minutes'))
                {
                    ord.Bpcs_Integration_Status__c = response.split('/')[1];
                }else{
                    ord.Bpcs_Integration_Status__c = response;
                }
                update ord;
                return 'Updated Successfully';
            }
            return response;
        }else{
            order = (Order)Json.deserialize(response,Order.Class);
            system.debug('JSON Order::'+order);
            order.Id = recordId;
            Order updateOrder = new Order();
            updateOrder.Id = recordId;
            updateOrder.BPCS_Order_number__c = order.BPCS_Order_number__c;
            updateOrder.Containers_BPCS_No__c = order.BPCS_Order_number__c;
            updateOrder.Bpcs_Integration_Status__c = order.Bpcs_Integration_Status__c;
            if(order.Status=='E' || order.Status=='H'){
                updateOrder.Containers_Order_Status__c ='Entered';
            }
            if(confDate!=null){
                updateOrder.Containers_Order_Status__c ='Confirmed';
            }    
            system.debug('Update Order::'+updateOrder);
            update updateOrder;
            return 'Updated Successfully';
        }
    }
    
    
    @auraEnabled
    public static String updateProductItemNumber(Id recordId,String itemNumber)
    {
        System.debug(itemNumber);
        Map<String,Sobject> mapProducts=makeProductCallout(itemNumber);
        if(mapProducts.containsKey('Success'))
        {
            Product2 prod=(Product2)mapProducts.get('Success');
            prod.ID = recordId;
            prod.Containers_Item_Number__c = itemNumber;
            update prod;
            if(mapProducts.containsKey('Sync Successful'))
            {
                Product2 prot=(Product2)mapProducts.get('Sync Successful');
                if(!Boolean.valueOf(prot.Name))
                {
                    return 'Sync Successful';
                }
            }
        }else{
            for(String str:mapProducts.keySet())
            {
                return 'Error: '+str; 
            }
        }
        
        return 'Record Updated';
    }
    
    /*@auraEnabled
    public static String updateArcosaProductItemNumber(Id recordId,String itemNumber)
    {
        System.debug(itemNumber);
        Map<String,Sobject> mapProducts=makeArcosaProductCallout(itemNumber);
        if(mapProducts.containsKey('Success'))
        {
            Containers_Arcosa_Tank_Product__c prod=(Containers_Arcosa_Tank_Product__c)mapProducts.get('Success');
            prod.ID = recordId;
            //prod.Containers_Item_Number__c = itemNumber;
            update prod;
            if(mapProducts.containsKey('Sync Successful'))
            {
                Containers_Arcosa_Tank_Product__c prot=(Containers_Arcosa_Tank_Product__c)mapProducts.get('Sync Successful');
                if(!Boolean.valueOf(prot.Name))
                {
                    return 'Sync Successful';
                }
            }
        }else{
            for(String str:mapProducts.keySet())
            {
                return 'Error: '+str; 
            }
        }
        
        return 'Record Updated';
    }*/
    
    @auraEnabled
    public static String updateAcctCustomerNumber(Id recordId,String customerNumber)
    {
        System.debug(customerNumber);
        Map<String,Sobject> mapAccounts=makeAccountCallout(customerNumber);
        if(mapAccounts.containsKey('Success'))
        {
            Account acct=(Account)mapAccounts.get('Success');
            acct.ID = recordId;
            acct.Containers_Customer_Number__c = customerNumber;
            update acct;
            if(mapAccounts.containsKey('Sync Successful'))
            {
                Account acc=(Account)mapAccounts.get('Sync Successful');
                if(!Boolean.valueOf(acc.Name))
                {
                    return 'Sync Successful';
                }
            }
        }else{
            for(String str:mapAccounts.keySet())
            {
                return 'Error: '+str; 
            }
        }
        return 'Record Updated';
    }
    
    private static String fetchAccountInfo(Id recordId)
    {
        System.debug(recordId);
        Account acct=[Select Id,Containers_Customer_Number__c from Account Where Id =: recordId];
        System.debug(acct.Containers_Customer_Number__c);
        if(acct.Containers_Customer_Number__c== null)
        {
            return 'No Account match';    
        }else{
            return updateAcctCustomerNumber(recordId,acct.Containers_Customer_Number__c);
        }
        //return null;
    }
    
    
    private static String fetchProductInfo(Id recordId)
    {
        System.debug(recordId);
        if(recordId.getSObjectType().getDescribe() == Schema.SobjectType.Product2)
        {
            Product2 product2=[Select Id,Containers_Item_Number__c from Product2 Where Id =: recordId];
            System.debug(product2.Containers_Item_Number__c);
            if(product2.Containers_Item_Number__c == null)
            {
                return 'No Product match';    
            }else{
                return updateProductItemNumber(recordId,product2.Containers_Item_Number__c);
            }
        }/*else if(recordId.getSObjectType().getDescribe() == Schema.SobjectType.Containers_Arcosa_Tank_Product__c){
            Containers_Arcosa_Tank_Product__c product=[Select Id,Containers_Item__c from Containers_Arcosa_Tank_Product__c Where Id =: recordId];
            System.debug(product.Containers_Item__c);
            if(product.Containers_Item__c == null)
            {
                return 'No Product match';    
            }else{
                return updateArcosaProductItemNumber(recordId,product.Containers_Item__c);
            }
        }*/
        return null;
    }
    
    private static String fetchOrderInfo(Id recordId)
    {
        System.debug(recordId);
        Order order=[Select Id,BPCS_Order_number__c,Containers_Order_Inv_No__c,ShippingStreet,ShippingCity,ShippingState,ShippingCountry,ShippingPostalCode from Order Where Id =: recordId];
        if(order.BPCS_Order_number__c == null &&  order.Containers_Order_Inv_No__c == null)
        {
            return 'No Order match';    
        }else{
            String address=order.ShippingStreet +(order.ShippingStreet != null?',':'')+ order.ShippingCity + (order.ShippingCity != null?',':'')+
                         order.ShippingState+ (order.ShippingState != null?',':'')+order.ShippingCountry+(order.ShippingCountry != null?',':'')+order.ShippingPostalCode;
            
            return makeOrderCallout(String.valueOf(order.Containers_Order_Inv_No__c),order.BPCS_Order_number__c,address);
            //return fetchOrderInfo(recordId,product2.Containers_Item_Number__c);
        }
        //return null;
    }
    
    public Static Boolean allFieldsValue=false;
    
    private static String parseObject(Object obj)
    {
        String fValue=(String)obj;
        if(fValue != null)
        {
            return fValue;    
        }else{
            allFieldsValue =true;
            return '';
        }
        
    }
    
    
    private static Map<String,Sobject> makeAccountCallout(String itemNumber)
    {
        try{
            String body='{"CustomerNumber": "'+itemNumber+'"}';
            HttpResponse response=makeCallout(body,'https://connect.trin.net/ws/simple/getBpcsCustomerJson');
            if(response.getStatusCode() ==200)
            {
                Map<String,Object> root = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
                System.debug(root.get('GetBpcsItemResponse'));
                Object Item=root.get('GetBpcsItemResponse');
                Map<String,Object> mapItem = (Map<String,Object>)root;
                Object status=mapItem.get('status');
                if((String)status == 'Success')
                {
                    Object fields=mapItem.get('Customer');
                    Account acct=new Account();
                    for(Object obj:(List<Object>)fields)
                    {
                        Map<String,Object> record = (Map<String,Object>)obj;
                        System.debug(record.get('CustomerNumber'));
                        acct.Name =parseObject(record.get('CustomerName'));
                        acct.BillingStreet =parseObject(record.get('BillAddr1'));
                        acct.BillingCity =parseObject(record.get('BillCity'));
                        acct.BillingState =parseObject(record.get('BillState'));
                        acct.BillingPostalCode =parseObject(record.get('BillZip'));
                        acct.BillingCountry=parseObject(record.get('BillCountry'));
                        acct.phone =parseObject(record.get('BillPhone'));
                        acct.Containers_Address_Line_1__c= parseObject(record.get('MainAddr1'));
                        acct.Containers_Address_Line_2__c =parseObject(record.get('MainCity'));
                        acct.Containers_City__c =parseObject(record.get('MainCity'));
                        acct.Containers_State__c =parseObject(record.get('MainState'));
                        acct.Containers_Country__c =parseObject(record.get('MainCountry'));
                        acct.Containers_Zip__c =parseObject(record.get('MainZip'));
                        if(record.get('FreightTermCode') != 'NULL')
                        {
                            acct.Containers_Freight_Terms__c =parseObject(record.get('FreightTermCode'));
                        }
                        if(record.get('PaymentTermCode') != 'NULL')
                        {
                            acct.Containers_Payment_Terms__c = parseObject(record.get('PaymentTermCode'));
                        }
                        //System.debug(record.get('BillContact'));
                    }
                    return new Map<String,Account>{(String)status=>acct,'Sync Successful'=>new Account(Name=String.valueOf(allFieldsValue))};
                }else{
                    return new Map<String,Account>{(String)status=>null};
                }
            }else{
                return new Map<String,Account>{'Error: '+response.getBody()=>null};    
            }
        }catch(Exception e)
        {
            return new Map<String,Account>{'Error: '+e.getMessage()=>null};
        }
    }
    
    /*private static Map<String,Sobject> makeArcosaProductCallout(String itemNumber)
    {
        try{
            String body='{"GetBpcsItemRequest": { "ItemNumber": "'+itemNumber+'" }}';
            String endpoint ='https://connect.trin.net/ws/simple/getBpcsItemByNumberJson';
            HttpResponse response=makeCallout(body,endpoint);
            if(response.getStatusCode() ==200)
            {
                Map<String,Object> root = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
                System.debug(root.get('GetBpcsItemResponse'));
                Object Item=root.get('GetBpcsItemResponse');
                Map<String,Object> mapItem = (Map<String,Object>)Item;
                Object status=mapItem.get('status');
                if((String)status == 'Success')
                {
                    Object Items=mapItem.get('Item');
                    Containers_Arcosa_Tank_Product__c product=new Containers_Arcosa_Tank_Product__c();
                    for(Object obj:(List<Object>)Items)
                    {
                        Map<String,Object> record = (Map<String,Object>)obj;
                        System.debug(record.get('Actual_Cost_per_Unit'));
                        product.Containers_Item_Descr__c =parseObject(record.get('Item_Description'));
                        product.Containers_Extra_Descr__c = parseObject(record.get('Extra_Description'));
                        product.Containers_Item_Class__c =parseObject(record.get('ItemClass'));
                        product.Containers_Item_Class_Descr__c =parseObject(record.get('ItemClassDesc'));
                        product.Containers_Tank_Volume__c =parseObject(record.get('Volume'));
                        
                        System.debug(record.get('Drawing_Number'));
                        System.debug(record.get('Drop_Ship_Allowed'));
                        System.debug(record.get('Frozen_Standard_Cost'));
                        System.debug(record.get('Record_ID'));
                        System.debug(record.get('Days_Lead_Time'));
                        System.debug(record.get('Price_Field'));
                        System.debug(record.get('Group_Sales_Analysis_Field'));
                        System.debug(record.get('Standard_Cost_per_Unit'));
                        System.debug(record.get('Selling_Unit_of_Measure'));
                    }
                    return new Map<String,Sobject>{(String)status=>product,'Sync Successful'=>new Containers_Arcosa_Tank_Product__c(Name=String.valueOf(allFieldsValue))};
                }else{
                    return new Map<String,Sobject>{(String)status=>null};
                }
            }else{    
                return new Map<String,Sobject>{'Error: '+response.getBody()=>null};
            }
        }catch(Exception e)
        {
            return new Map<String,Sobject>{'Error: '+e.getMessage()=>null};
        }
    }*/
    
    private static Map<String,Sobject> makeProductCallout(String itemNumber)
    {
        try{
            String body='{"GetBpcsItemRequest": { "ItemNumber": "'+itemNumber+'" }}';
            String endpoint ='https://connect.trin.net/ws/simple/getBpcsItemByNumberJson';
            HttpResponse response=makeCallout(body,endpoint);
            if(response.getStatusCode() ==200)
            {
                Map<String,Object> root = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
                System.debug(root.get('GetBpcsItemResponse'));
                Object Item=root.get('GetBpcsItemResponse');
                Map<String,Object> mapItem = (Map<String,Object>)Item;
                Object status=mapItem.get('status');
                if((String)status == 'Success')
                {
                    Object Items=mapItem.get('Item');
                    product2 product=new product2();
                    for(Object obj:(List<Object>)Items)
                    {
                        Map<String,Object> record = (Map<String,Object>)obj;
                        System.debug(record.get('Actual_Cost_per_Unit'));
                        product.Containers_Item_Descr__c =parseObject(record.get('Item_Description'));
                        product.Containers_Extra_Descr__c = parseObject(record.get('Extra_Description'));
                        product.Containers_Item_Number__c =parseObject(record.get('Item_Number'));
                        product.Containers_Item_Class__c =parseObject(record.get('ItemClass'));
                        product.Containers_Item_Class_Descr__c =parseObject(record.get('ItemClassDesc'));
                        product.Containers_Tank_Volume__c =parseObject(record.get('Volume'));
                        
                        System.debug(record.get('Drawing_Number'));
                        System.debug(record.get('Drop_Ship_Allowed'));
                        System.debug(record.get('Frozen_Standard_Cost'));
                        System.debug(record.get('Record_ID'));
                        System.debug(record.get('Days_Lead_Time'));
                        System.debug(record.get('Price_Field'));
                        System.debug(record.get('Group_Sales_Analysis_Field'));
                        System.debug(record.get('Standard_Cost_per_Unit'));
                        System.debug(record.get('Selling_Unit_of_Measure'));
                    }
                    return new Map<String,Sobject>{(String)status=>product,'Sync Successful'=>new Product2(Name=String.valueOf(allFieldsValue))};
                }else{
                    return new Map<String,Sobject>{(String)status=>null};
                }
            }else{    
                return new Map<String,Sobject>{'Error: '+response.getBody()=>null};
            }
        }catch(Exception e)
        {
            return new Map<String,Sobject>{'Error: '+e.getMessage()=>null};
        }
    }
    
    public Class InvoiceWrapper
    {
        @auraEnabled
        public String Invoice {get;set;}
        @auraEnabled
        public String TaxAmount {get;set;}
        @auraEnabled
        public String FreightCharge {get;set;}
        @auraEnabled
        public String Invoice_Total {get;set;}
        @auraEnabled
        public String Invoice_Date{get;set;}
        @auraEnabled
        public String NoOflines {get;set;}
        @auraEnabled
        public String DateShipped {get;set;}
        @auraEnabled
        public String ShipVia {get;set;}
        @auraEnabled
        public List<InvoiceLineWrapper> lstInvoiceLineWrapper {get;set;}
    }
    
    public Class InvoiceLineWrapper
    {
        @auraEnabled
        public String Line {get;set;}
        @auraEnabled
        public String Item {get;set;}
        @auraEnabled
        public String Qty{get;set;}
        @auraEnabled
        public String NetPrice{get;set;}
    }
    
    
    
    @auraEnabled
    public static String makeOrderCallout(String externalOrderNumber,String BpcsOrderNumber,String shippingAddress)
    {
        try{
            system.debug('externalOrderNumber::'+externalOrderNumber);
            system.debug('BpcsOrderNumber::'+BpcsOrderNumber);
            system.debug('shippingAddress::'+shippingAddress);
            OrderWrapper oWrapper=new OrderWrapper();
            List<String> lstString=new List<String>();
            Map<String,String> mapfrightTermsvalues=new Map<String,String>();
            Map<String,String> mapPaymentTermsvalues=new Map<String,String>();
            for(Schema.PicklistEntry frightTerms:Schema.SobjectType.Order.fields.Containers_Freight_Terms__c.getPickListValues())
            {
                mapfrightTermsvalues.put(frightTerms.getValue(),frightTerms.getLabel());
            }
            
            for(Schema.PicklistEntry paymentTerms:Schema.SobjectType.Order.fields.Containers_Payment_Terms__c.getPickListValues())
            {
                mapPaymentTermsvalues.put(paymentTerms.getValue(),paymentTerms.getLabel());
            }
                
            System.debug(externalOrderNumber);
            if(externalOrderNumber != null)
            {
                lstString.add('"ExternalOrderNumber": "'+ externalOrderNumber + '"');//'071119-5004'
            }
            
            if(BpcsOrderNumber != null)
            {
                lstString.add('"BpcsOrderNumber": "'+BpcsOrderNumber+ '"');//'877738'    
            }
            
            List<Container_Environment__mdt> lstEnvironment=[Select Id,DeveloperName from Container_Environment__mdt];
            if(!lstEnvironment.isEmpty())
            {
                lstString.add('"Environment": "'+lstEnvironment[0].DeveloperName+ '"');
            }
            
            
            String body='{"GetBpcsOrderByNumberRequest": {' + String.join(lstString,',')+'}}';
            String endpoint ='https://connect.trin.net/ws/simple/getBpcsOrderByNumberJson';
            system.debug('JSON Request Body :: '+body);
            system.debug('Endpoint :: '+endpoint);
            
            HttpResponse response=makeCallout(body,endpoint);
            system.debug('response.getStatusCode()::'+response.getStatusCode());
            if(response.getStatusCode() ==200)
            {
                Map<String,Object> root = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
                System.debug('BpcsOrderList::'+root.get('BpcsOrderList'));
                Object Item=root.get('BpcsOrderList');
                Map<String,Object> mapItem = (Map<String,Object>)Item;
                Object status=mapItem.get('status');
                String bpcsIntegrationStatus = (String)mapItem.get('statusDesc'); 
                if((String)status == 'Success')
                {
                    product2 product=new product2();
                    for(Object obj:(List<Object>)mapItem.get('BpcsOrder'))
                    {
                        Map<String,Object> record = (Map<String,Object>)obj;
                        Object orderHeader=record.get('OrderHeader');
                        Map<String,Object> orderValues = (Map<String,Object>)orderHeader;
                        System.debug(orderValues);
                        Order order=new Order();
                        
                        order.Bpcs_Integration_Status__c = bpcsIntegrationStatus;
                        order.BPCS_Order_number__c = (String)orderValues.get('OrderNumber');
                        order.Containers_Customer_PO__c =(String)orderValues.get('CustomerPO');
                        order.PoDate =parseDate(orderValues.get('PODate'));
                        order.Type =(String)orderValues.get('OrderType');
                        if(mapPaymentTermsvalues.containskey((String)orderValues.get('PaymentTermCode')) && !Test.isRunningTest())
                            order.Containers_Payment_Terms__c=mapPaymentTermsvalues.get((String)orderValues.get('PaymentTermCode'));
                        order.Containers_WareHouse__c=(String)orderValues.get('WarehouseCode');
                        if(mapfrightTermsvalues.containsKey((String)orderValues.get('FreightTermCode')) && !Test.isRunningTest())
                            order.Containers_Freight_Terms__c=mapfrightTermsvalues.get((String)orderValues.get('FreightTermCode'));
                        order.Containers_Ship_Via__c=(String)orderValues.get('ShipVia');
                        System.debug(orderValues.get('TaxableFlag'));
                        if(!Test.isRunningTest()){
                            order.Containers_Sales_Rep__c=(String)orderValues.get('SalesmanNumber');
                        }
                        order.Ship_To_Name__c=(String)orderValues.get('ShipToName');
                        order.ShippingStreet=(String)orderValues.get('ShipToAddr1');
                        order.ShippingCity=(String)orderValues.get('ShipToCity');
                        order.ShippingState=(String)orderValues.get('ShipToState');
                        order.ShippingPostalCode=(String)orderValues.get('ShipToZipcode');
                        order.ShippingCountry=(String)orderValues.get('ShipToCountry');
                        order.Status=(String)orderValues.get('OrderStatusCode');
                        order.Type = (String)orderValues.get('OrderStatus');
                        
                        order.MEX_RequestDate__c = parseDate(orderValues.get('RequestDate'));
                        order.Containers_Schedule_Date__c= parseDate(orderValues.get('ScheduleDate'));
                        
                        order.MEX_FreightDollarAmount__c= Decimal.valueOf(String.valueOf(orderValues.get('FreightAmount')));
                        order.Containers_EDIShipToNumber__c =(String)orderValues.get('EDIShipToNumber');
                        oWrapper.orderRecord=order;
                        
                        Object orderLines=record.get('OrderLineList');
                        Map<String,Object> orderLinesList = (Map<String,Object>)orderLines;
                        List<OrderItem> lstOrderItems=new List<OrderItem>();
                        for(Object OLines:(List<Object>)orderLinesList.get('OrderLine'))
                        {
                            System.debug(OLines);
                            Map<String,Object> OLine = (Map<String,Object>)OLines;
                            OrderItem oItem=new OrderItem();
                            oItem.MEX_Line_number__c=Decimal.valueOf((String)OLine.get('LineNumber'));
                            oItem.TMAT_Product_Code__c=(String)OLine.get('PartNumber');
                            oItem.TMAT_Product_Description__c=(String)OLine.get('PartDesc');
                            oItem.Quantity = Decimal.valueOf((String)OLine.get('Quantity'));
                            oItem.UnitPrice = Decimal.valueOf((String)OLine.get('Quantity')) * Decimal.valueOf((String)OLine.get('UnitPrice'));
                            oItem.MEX_RequestDate__c=parseDate(OLine.get('RequestDate'));
                            oItem.MEX_ScheduleShipDate__c=parseDate(OLine.get('ScheduleShipDate'));
                            lstOrderItems.add(oItem);
                        }
                        if(!lstOrderItems.isEmpty())
                        {
                            oWrapper.orderLineRecords =lstOrderItems;
                        }
                        
                    }
                    return Json.serialize(oWrapper);
                }else if((String)status == 'No_Data_Found'){
                    return 'Error: ' + (String)mapItem.get('statusDesc');
                }else if((String)status == 'Failed'){
                    return 'Error: ' + (String)mapItem.get('statusDesc');
                }
                else{
                    return 'No Data Found';
                }
            }else{    
                return 'Error: '+response.getBody();
            }
        }catch(Exception e)
        {
            return 'Error: '+e.getMessage()+e.getStacktraceString();
        }
    }
    
    @auraEnabled
    public static String makeOrderInvoiceCallout(Id recordId,String orderNumber)
    {
        try{
            System.debug(recordId);
            System.debug(orderNumber);
            OrderWrapper oWrapper=new OrderWrapper();
            Order order=[Select Id,BPCS_Order_number__c from Order Where Id = : recordId];
            if(order.BPCS_Order_number__c == null && orderNumber == null)
            {
                return 'No Order match';
            }
            String body='{"GetInvoiceByOrderNumber": { "OrderNumber": "'+(order.BPCS_Order_number__c != null?order.BPCS_Order_number__c:orderNumber) +'" }}';//
            String endpoint ='https://connect.trin.net/ws/simple/getBpcsInvoiceByOrderNumberJson';
            HttpResponse response=makeCallout(body,endpoint);
            if(response.getStatusCode() ==200)
            {
                Map<String,Object> root = (Map<String,Object>)JSON.deserializeUntyped(response.getBody());
                System.debug(root.get('InvoiceList'));
                Object Item=root.get('InvoiceList');
                Map<String,Object> mapItem = (Map<String,Object>)Item;
                Object status=mapItem.get('Status');
                if((String)status == 'Success')
                {
                    product2 product=new product2();
                    InvoiceWrapper wrap=new InvoiceWrapper();
                    List<InvoiceLineWrapper> lstInvoiceWrap=new List<InvoiceLineWrapper>();
                    for(Object obj:(List<Object>)mapItem.get('InvoiceLine'))
                    {
                        Map<String,Object> record = (Map<String,Object>)obj;
                        wrap.Invoice =(String)record.get('Invoice_Number');
                        wrap.TaxAmount  =(String)record.get('Tax_Amount');
                        wrap.FreightCharge=(String)record.get('Freight_Charge');
                        wrap.Invoice_Total=(String)record.get('Invoice_Total');
                        wrap.Invoice_Date=(String)record.get('Invoice_Date');
                        wrap.NoOflines=(String)record.get('Number_of_Lines_on_the_Invoice');
                        wrap.DateShipped=(String)record.get('Date_Order_Was_Shipped');
                        wrap.ShipVia=(String)record.get('Invoice_Ship_via_Desc');
                        
                        InvoiceLineWrapper iWrap=new InvoiceLineWrapper();
                        iWrap.Line=(String)record.get('Invoice_Line_Number');
                        iWrap.Item=(String)record.get('Item');
                        iWrap.Qty=(String)record.get('Quantity');
                        iWrap.NetPrice=(String)record.get('Net_Price');
                        lstInvoiceWrap.add(iWrap);
                    }
                    
                    if(!lstInvoiceWrap.isEmpty())
                    {
                        wrap.lstInvoiceLineWrapper =lstInvoiceWrap;
                    }
                    return Json.serialize(wrap);
                }else{
                    return 'No Data Found';
                }
            }else{    
                return 'Error: '+response.getBody();
            }
        }catch(Exception e)
        {
            
            return 'Error: '+e.getMessage()+e.getStacktraceString();
        }
        
    }
    
    private static Date parseDate(Object dateObject)
    {
        if(dateObject != null)
        {
            String datevalue =String.valueOf(dateObject);
            String year=datevalue.subString(0,4);
            String month=datevalue.subString(4,6);
            String day=datevalue.subString(6,8);
            System.debug(datevalue);
            Date dt=date.parse(month+'/'+day+'/'+year);
            System.debug(dt);
            return dt;    
        }else
            return null;
        
    }
    
    private static HttpResponse makeCallout(String body,String endPointUrl)
    {
            System.debug(body);
            Http h2 = new Http();
            HttpRequest req1 = new HttpRequest();
            req1.setHeader('Authorization','Basic '+EncodingUtil.base64Encode(Blob.valueOf('oraclecpq@trinityindustriesinc-HUUL4D' + ':' + 'f58e8a6d-2131-4764-8747-c4e1e302d74a')));
            req1.setHeader('Content-Type','application/json');
            req1.setHeader('accept','application/json');
            req1.setBody(body);
            req1.setMethod('POST');
            req1.setEndpoint(endPointUrl);
            HttpResponse response = h2.send(req1);
            System.debug(response.getBody());
            return response;
        
        //return response.getBody();
    }
}