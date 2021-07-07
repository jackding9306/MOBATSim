classdef VehiclePathPlanner_Astar < VehiclePathPlanner
    % VehiclePathPlanner_A* Inherits the VehiclePathPlanner. Generates a path to reach the destination waypoint.
    %
    % This template includes the minimum set of functions required
    % to define a System object with discrete state.
    
    methods
        % Constructor
        function obj = VehiclePathPlanner_Astar(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:});
        end
    end
    
    methods (Access = protected)
        
        function setupImpl(obj)
            setupImpl@VehiclePathPlanner(obj); % Inherit the setupImpl function of the Superclass @VehiclePathPlanner
        end
        
        function FuturePlan = findPath(obj,OtherVehiclesFutureData)
                        
            starting_point = obj.vehicle.pathInfo.lastWaypoint;
            ending_point = obj.vehicle.pathInfo.destinationPoint;
            
            [Path,newFutureData] = obj.AStarPathfinder(obj.vehicle, starting_point, ending_point, obj.getCurrentTime, OtherVehiclesFutureData);
            
            obj.vehicle.setPath(Path);
            FuturePlan = newFutureData; 
        end
        
        
        function [path, newFutureData] = AStarPathfinder(obj, car, startingPoint, endingPoint, global_timesteps, futureData)
            %This function performs a normal A* search inside the Digraph.
            %OUTPUT: newFutureData = | car.id | RouteID | Estimated Average Speed | Estimated Entrance Time | Estimated Exit Time |
            %path = [nr of nodes from start to finish]
            %% Initialization
            if isempty(futureData)
                futureData = [0 0 0 0 0 -1]; % 1x6 to fit the output size
            end
            
            % Create a table for all the waypoints (nodes) where each row index is an identifier for a waypoint
            waypoints =  zeros(length(obj.Map.waypoints),7); % initialize with zeros (later could be turned into table but might lead to overhead)
            % --------------------------------------------Waypoints Structure----nx7-----------------------------------------------------
            % | State of Waypoint | Current Node | Current Route | Current Speed | Time Costs | Time + Heuristic Costs | Total distance |
            
            %get maximum speed for every edge
            maxSpeed = car.dynamics.maxSpeed ;
            currentSpeed = car.dynamics.speed ;
            speedRoutes = [obj.Map.connections.circle(:,end);obj.Map.connections.translation(:,end)];
            maxSpeedRoutes = speedRoutes;
            maxSpeedRoutes(speedRoutes>maxSpeed)= maxSpeed; %possible speed for every route
            
            connections = obj.Map.connections.all;
            
            distances = obj.Map.connections.distances;
            
            currentNode = startingPoint; %currentNode: current Node from where to expand neighbour Nodes
            waypoints(startingPoint,5) = global_timesteps;
            waypoints(startingPoint,4) = currentSpeed;
            
            %% main loop
            while (1)
                waypoints(currentNode,1) = 2; %set state of waypoint to 2 -> waypoint in closed List
                
                %% find neighbours
                routes2neighbourNode = find(connections(:,1) == currentNode); % route ID
                neighbourNodes = connections(connections(:,1) == currentNode,2); % waypointID of neighbour
                neighbourNodes_Routes = [neighbourNodes'; routes2neighbourNode'];
                %% loop over all neighbours
                for neighbourNode_Route=neighbourNodes_Routes
                    neighbourWP = waypoints(neighbourNode_Route(1),:); % waypointID of neighbour
                    currentTime = waypoints(currentNode,5); % time the car will reach the node
                    currentTotalDistance = waypoints(currentNode,7); %distance travveled unto this node
                    currentSpeed = waypoints(currentNode,4); % the speed of the car when entering the node
                    currentRoute = neighbourNode_Route(2); % route ID
                    
                    currentMaxSpeedRoutes = maxSpeedRoutes;
                    
                    %% If the vehicle is still in the acceleration phase
                    timeToReach = distances(currentRoute)/ currentMaxSpeedRoutes(currentRoute); %timesteps to reach neighbour
                    nextSpeed = maxSpeed;
                    
                    %% check for other cars on same route (using merged future data)
                    %get every future data info for the current edge
                    currentFutureData = futureData(futureData(:,2) == currentRoute,:);
                    %relevant data has to contain an arrival time before
                    %current car and an exit time after that car
                    currentFutureData = currentFutureData(currentFutureData(:,4)<= currentTime & currentFutureData(:,5)>currentTime,:);
                    if ~isempty(currentFutureData)
                        %% disturbing car on same route
                        %search for the highest exit time, that will slow
                        %us down the most
                        index = find(max(currentFutureData(:,5)));%TODO use max function properly
                        timeToReachDisturbingVehicle = currentFutureData(index,5);
                        %get speed of the slower vehicle
                        speedDisturbingVehicle =  currentFutureData(index,3);
                        %currentTime = entry time of the edge
                        %timeToReach = how long does it take to drive over current edge
                        %timeToReachDisturbingVehicle = exit time of other vehicle
                        %differnce = current car exit time - other car exit time
                        timeDifference = (currentTime + timeToReach) - timeToReachDisturbingVehicle ;
                        
                        spacingTime = 6;
                        if (timeDifference < spacingTime)
                            timeToReach = timeToReachDisturbingVehicle + spacingTime - currentTime;
                            nextSpeed = speedDisturbingVehicle;
                        end
                        
                        
                    end
                    
                    %% calculate costs (costs = distance/speed)
                    costs = timeToReach;
                    
                    %% calculate heuristic (Luftlinie)
                    heuristicCosts = 1/maxSpeed * norm(get_coordinates_from_waypoint(obj.Map, neighbourNode_Route(1))-get_coordinates_from_waypoint(obj.Map, endingPoint));
                    
                    
                    %% update waypoints array
                    if neighbourWP(1) == 0
                        neighbourWP(2) = currentNode;
                        
                        neighbourWP(5) = waypoints(currentNode,5) + costs;
                        neighbourWP(1) = 1;
                        neighbourWP(3) = currentRoute;
                        neighbourWP(4) = nextSpeed;
                        neighbourWP(6) = waypoints(currentNode,5) + costs + heuristicCosts;
                        neighbourWP(7) = waypoints(currentNode,7) + distances(currentRoute) ;
                        
                    elseif  neighbourWP(1) == 1
                        
                        %% replace costs if smaller
                        if  (waypoints(currentNode,5)+ costs < neighbourWP(5))
                            
                            neighbourWP(2) = currentNode;
                            neighbourWP(5) = waypoints(currentNode,5) + costs;
                            neighbourWP(3) = currentRoute;
                            neighbourWP(4) = nextSpeed;
                            neighbourWP(6) = waypoints(currentNode,5 )+ costs + heuristicCosts;
                            neighbourWP(7) = waypoints(currentNode,7) + distances(currentRoute);
                            
                        end
                    end
                    waypoints(neighbourNode_Route(1),:) = neighbourWP;
                end
                
                
                %% loop exit conditions
                if ismember(1,waypoints(:,1)) % Check if there is any node with state 1 (open and touched)
                    minCosts = min(waypoints(waypoints(:,1) == 1,6)); % get waypoint with min costs
                else
                    break
                end
                
                if waypoints(endingPoint,1) ~= 0 % check if waypoint state is 1 or 2
                    if minCosts >  waypoints(endingPoint)
                        % Uncomment the code below to convert the waypoints into table to analyze
                        % array2table(waypoints,'VariableNames',{'State of Waypoint','Current Node','Current Route','Current Speed','Time Costs','Time + Heuristic Costs','Total distance'})
                        break
                    end
                end
                
                %% get new waypoint to analyze -> next iteration in loop
                currentNode =  find(waypoints(:,6) == minCosts& waypoints(:,1)==1);
                currentNode = currentNode(1);
                
            end
            
            % Compose the path by using the analyzed waypoints array
            path = obj.composePath(waypoints, startingPoint, endingPoint);
            
            %% updateFuture Date of this vehicle
            newFutureData = zeros((length(path)-1),6); %Matrix Preallocation
            for i = 1: (length(path)-1)
                newFutureData(i,:) = [car.id waypoints(path(i+1),3) waypoints(path(i+1),4) waypoints(path(i),5)  waypoints(path(i+1),5) -1];
            end
            
            car.logInitialFuturePlan(newFutureData,global_timesteps);
                        
        end
        
        function OtherVehiclesFutureData = deleteCollidedVehicleFutureData(obj,OtherVehiclesFutureData)
            
            otherCarIDs = unique(OtherVehiclesFutureData(:,1))'; % OtherCars which have the same FutureData            
            
            % other cars with same future data found
            if otherCarIDs %#ok<BDSCI,BDLGI>                
                % find collided cars
                otherCars = obj.Map.Vehicles(otherCarIDs);
                collidedCarIDs = otherCarIDs([cat(1,otherCars.status).collided] == 1);
                
                if collidedCarIDs
                    % remove future data from collided cars
                    OtherVehiclesFutureData(ismember(OtherVehiclesFutureData(:,1),collidedCarIDs),:) = [];
                end
            end
            
        end
    end
    
    
end