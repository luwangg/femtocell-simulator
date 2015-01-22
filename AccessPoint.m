classdef AccessPoint < matlab.System

    % ToDo:
    % 1. PRB placement smartly or ok-smartly
    % 2. Enviromental variablity (Sensing)+++
    % 3. Fixed offset in time for voice calls
    % 4. Graph showing PRBs in use, not power levels (Easier to look at)
        % Possible histogram
        
    % Bugs:
    % 1.
    
    % Assumption:
    % 1. All channels are stack in the same band
    % 2. if channels are smaller they occupy same spectrum location
    
    properties
        attachedNodes = 0;
        nodeTasks
        resourceGrid
        bitQueueSize
        taskDuration
        apChannelBandwidth = 1.4e6;
        apID = 1;
        figID = 1;
        activeNodes
        nodeCodeRates
        nodeModulation
        apPosition
        maxAvailablePRBs = 0;
        nodePRMmap
        
        AllpathlossPairs
        AllAPs
    end
    
    methods
        function obj = AccessPoint(ID)
            obj.apID = ID;
        end
    end
    
    methods (Access = protected)
        function setupImpl(obj,~)
            
            [obj.bitQueueSize, obj.taskDuration, obj.nodeTasks, obj.activeNodes, obj.nodeCodeRates]...
                = deal(zeros(obj.attachedNodes,1));
            
            obj.resourceGrid = generateGrid(obj.apChannelBandwidth);
            obj.nodePRMmap = zeros(obj.attachedNodes,size(obj.resourceGrid,1),size(obj.resourceGrid,2));
            
            obj.nodeModulation = cell(obj.attachedNodes,1);
            
        end
        
        function stepImpl(obj,nodeID)

            % Clear resource grid
            obj.resourceGrid = generateGrid(obj.apChannelBandwidth);
            
            obj.maxAvailablePRBs = numel(obj.resourceGrid);
            
            if obj.activeNodes(nodeID)
                disp('Updating Task');
                obj.updateCurrentTask(nodeID);
            else
                % Should I do something?
                transmit = poissrnd(0.5);
                if transmit
                    disp('Creating New Task');
                    obj.activeNodes(nodeID) = true;
                    obj.createTask(nodeID);
                end
            end
            
        end
        
        function createTask(obj,nodeID)
            
            % Update coderate and modulation
            obj.determineMCS(nodeID);
            
            % Pick task
            obj.nodeTasks(nodeID) = randi([0 1],1,1);
            switch obj.nodeTasks(nodeID)
                case 0 % Voice
                    disp('Making a call');
                    obj.taskDuration(nodeID) = 30; %Radio Frames to last over
                    obj.bitQueueSize(nodeID) = 300;
                    
                case 1 % Website Visit
                    disp('Visiting a website');
                    obj.taskDuration(nodeID) = -1; %Not used for task
                    obj.bitQueueSize(nodeID) = 10e3;
            end
            disp(['Queue Size: ',num2str(obj.bitQueueSize(nodeID))]);
            
            % Update resource grid
            obj.applyResourcesToGrid(nodeID)
            
        end
        
        function updateCurrentTask(obj,nodeID)
            
            % Update active nodes
            if obj.taskDuration(nodeID) == 0
                obj.activeNodes(nodeID) = false;
                
%                 % Deallocate resources
%                 map = obj.nodePRMmap(nodeID,:,:)>0;
%                 obj.resourceGrid(map) = 0;
                
            elseif (obj.taskDuration(nodeID)==-1) && (obj.bitQueueSize(nodeID) == 0)
                obj.activeNodes(nodeID) = false;
                
%                 % Deallocate resources
%                 map = obj.nodePRMmap(nodeID,:,:)>0;
%                 obj.resourceGrid(map) = 0;
            end
            
            % Update coderate and modulation
            obj.determineMCS(nodeID);
            
            % If we have a streaming task add necessary bits to queue
            if obj.taskDuration > 0
                obj.updateQueue(nodeID) % Updates duration as well
            end
            disp(['Queue Size: ',num2str(obj.bitQueueSize(nodeID))]);
            
            % Update resource grid
            obj.applyResourcesToGrid(nodeID) % removes resources from queues
            
        end
        
        % For streaming tasks add new data to queue
        function updateQueue(obj,nodeID) 
            
            switch obj.nodeTasks(nodeID)
                case 0 % Voice
                    obj.taskDuration(nodeID) = obj.taskDuration(nodeID) - 1;
                    obj.bitQueueSize(nodeID) = 300;
                    
                otherwise
                    disp('Something Broke');
            end
            
        end
        
        
        function applyResourcesToGrid(obj,nodeID)
            
            % Get current channel info for coderate and modulation
            %fixed for now
            bits = obj.bitQueueSize(nodeID);
            
            % Convert bits to resource blocks and calculate how many we can
            % put into this transmission
            PRBs = obj.determineNeededPRBs( bits, nodeID ); % bit queue updated in call
            
            % Update remaining resources for other users
            obj.maxAvailablePRBs = obj.maxAvailablePRBs - PRBs;
            
            % Sense around what are the best channels to select
            %DO LATER
            % Sort PRBs by best avaiable
            %DO LATER
            
            
            
            % Select PRBs of remaining
            locationsOfSelectedPRBs = obj.selectBestPRBs(PRBs);
            
            % Add resouces to current grid
            %frequency = randi([1 size(obj.resourceGrid,1)],1,1);
            %offset = randi([1 (20-PRBs+1)],1,1);
            %obj.resourceGrid(frequency,offset:offset+PRBs-1) = 100;
            for k=1:size(locationsOfSelectedPRBs,1)
                    obj.resourceGrid(...
                        locationsOfSelectedPRBs(k,1),...
                        locationsOfSelectedPRBs(k,2)) = 100;
            end
            % Keep track of what user has what
            %obj.nodePRMmap(nodeID,frequency,offset:offset+PRBs-1) = 1;
            obj.nodePRMmap(locationsOfSelectedPRBs) = 1;
            
        end
        
        function indexs = selectBestPRBs(obj,numPRBs)
           
            combinedGrid = obj.SenseEnvirorment();
            % Select part of grid we have access to (is in our bandwidth)
            gridDims = size(obj.resourceGrid);
            myGrid = combinedGrid(1:gridDims(1),1:gridDims(2));
            
            % Convert to linear indexing 
            %gridIndex = reshape(1:numel(obj.resourceGrid),gridDims(1),gridDims(2));
            
            combinedGridLin = reshape(myGrid,gridDims(1)*gridDims(2),1);
            
            [value, indexs] = sort(combinedGridLin);
            
            % Select lowest possibly allocated channels
            
            
            % Extract elements left
%             availableInMatrixIndex = gridIndex(availablePBSindexs);
%             availableInMatrixIndex(availableInMatrixIndex==0) = [];
%             selectedIndexs = availableInMatrixIndex(1:numPRBs);
            selectedIndexs = indexs(1:numPRBs);
            
            % Now Get matrix index from these linear ones
            %[I,J] = ind2sub(gridDims,selectedIndexs.');
            %indexs = [I,J];
            row = mod(selectedIndexs+5,gridDims(1))+1;
            column = floor((selectedIndexs+5)/gridDims(1));
            indexs = [row,column];
            
        end
        
        function combinedGrid = SenseEnvirorment(obj)
            % Get combined energy from all 
            observer = obj.apID;
            combinedGrid = combinedGrids(obj.AllAPs,obj.AllpathlossPairs,observer);

        end
        
        % Calculate how many of the available blocks will be used
        function PRBallocated = determineNeededPRBs( obj, bits, nodeID )
            
            
            switch obj.nodeModulation{nodeID}
                case 'QPSK'
                    bitsPerSymbol = 2;
                case 'QAM16'
                    bitsPerSymbol = 4;
                case 'QAM64'
                    bitsPerSymbol = 6;
            end
            
            subcarriersPerPRB = 12;
            OFDMSymbolsPerPRB = 7;
            
            bitsPerResourceElement = bitsPerSymbol*obj.nodeCodeRates(nodeID);
            ResourceElementsPerPRB = subcarriersPerPRB * OFDMSymbolsPerPRB;
            bitsPRB = floor(ResourceElementsPerPRB * bitsPerResourceElement);
            
            requiredPRBs = ceil(bits/bitsPRB);
            %unroundedPRB = (bits/bitsPRB);
            
            % Remove necessary bits from queues since they are now
            % transmitted
            if requiredPRBs > obj.maxAvailablePRBs
                % Update queue to show remaining bits
                PRBallocated = obj.maxAvailablePRBs;
                obj.bitQueueSize(nodeID) = bits - obj.maxAvailablePRBs*bitsPRB;
            else
                PRBallocated = requiredPRBs;
                obj.bitQueueSize(nodeID) = 0;
            end
            
        end
        
        function determineMCS(obj,nodeID)
            
            %FIX LATER
            obj.nodeCodeRates(nodeID) = 948/1024;
            obj.nodeModulation{nodeID} = 'QPSK';
            
        end
        
    end
    
    methods
        function viewGrid(obj)
            
            figure(obj.figID);
            %subplot(aps,1,obj.apID);
            surf(obj.resourceGrid);
            view(0,90)
            xlabel('Resource Blocks (Time 1 Block=0.5ms)');
            ylabel('Resource Blocks (Frequency 1 Block=180KHz)');
            
        end
    end
    
end
