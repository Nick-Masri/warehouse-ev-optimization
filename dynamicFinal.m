
clc;
clear;
yalmip('clear');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Parameter Declaration %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%  Timeframe Parameters
D = 7;
T = 4*24*D;       % Number of timesteps
dt = .25;               % Duration of timesteps (h)
time = 15*(1:T)/60;     % Time vector for graphing purposes

% Set Size
B = 10;                 % Number of busses
numChargers = 3;            % number of chargers

% Bus Params
% eB_endPercent = .66;    % Percent of maximum charge at start and finish (kWh)
eB_max = 675;           % Maximum energy of busses (kWh)
eB_min = 135;           % Minimum energy of busses (kWh)

% Charger Params
pCB = 75;
pCB_min = 75;
eff_CB = .94;           % Efficiency of charging busses

% Main Storage Parameters
eM_max = 1000;          % Maximum energy of main storage (kWh)
eM_min = 200;           % Minimum energy of main storage (kWh)

pCM_max = 500;          % Maximum main storage charging power (kW)
pDM_max = 500;          % Maximum main storage discharging power (kW)
eff_CM = .90;           % Efficiency of charging main storage
eff_DM = .90;           % Efficiency of dischargin main storage

routes = [2, 9, 25, 98, 102, 134, 210, 6, 212, 69];

R = size(routes, 2);

eB_range = eB_max - eB_min;

[departure, arrival, eRoute, report] = initRoutesDynamically(routes, D, eB_range, pCB_min);
report

% creating tDep and tRet
tDep = zeros(R, D);
tRet = zeros(R, D);

for d = 1:D
    for r = 1:R
        tDep(r,d) = departure(r)+(d-1)*96;
        tRet(r,d) = arrival(r)+(d-1)*96;
    end
end


% creating tDay
tDay = zeros(D, 96);
for d = 1:D
    tDay(d,:) = (d-1)*96+1:d*96;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Input Data Generation %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



% Generate Solar Generation Profile
season = 'summer';
mornings = ["sunny","sunny","sunny","sunny","sunny","sunny","sunny"];
noons = ["sunny","sunny","sunny","sunny","sunny","sunny","sunny"];
nights = ["sunny","sunny","sunny","sunny","sunny","sunny","sunny"];

solarPowAvail = 250*initSolarPowModel(season, D, mornings, noons, nights);

% Generate Grid Availability Profile
gridPowAvail = 500*initGridAvailability('gridAvailData.xlsx', D);

% Generate Grid Pricing Profile
gridPowPrice = initGridPricingModel(D);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Mathematical Model %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

C = [];

%%%%%%%%%%
% Decision Variables
%%%%%%%%%%

% Main Storage
eM = sdpvar(1,T);
solarPowToM = sdpvar(1, T);
gridPowToM = sdpvar(1, T);
powerCM = sdpvar(1, T);
powerDM = sdpvar(1, T);

% Buses
powerCB = sdpvar(B, T); 
solarPowToB = sdpvar(B, T);
gridPowToB = sdpvar(B, T);
mainPowToB = sdpvar(B, T);
eB = sdpvar(B,T);
chargerUse = binvar(B,T);


% Route Coverage
assignment = binvar(B, D, R);

busLevel = 0.66;
reserveLevel = 1;

% charging activities
T1 = binvar(B,T);
T2 = binvar(B,T);
Change = binvar(B,T);
charging = binvar(B,D);

C = [C, Change == T1 + T2];


for t = 1:T
    for b = 1:B
         
        if t == 1
            C = [C, T1(b,t)==0];
            C = [C, T2(b,t)==0];
            
        else
            
            C = [C, T1(b,t)-T2(b,t) == chargerUse(b,t) - chargerUse(b,t-1)];
            C = [C, Change(b,t) <= chargerUse(b,t-1) + chargerUse(b,t)];
            C = [C, Change(b,t) <= 2 - chargerUse(b,t-1) - chargerUse(b,t)];
        end
        
    end           
end
    

for b = 1:B
    for d = 1:D
        C = [C, sum(Change(b, tDay(d, 1):tDay(d,96)), 'all') <= 2];
        C = [C, sum(chargerUse(b, tDay(d, 1):tDay(d,96)), 'all') >= 6*charging(b,d)];
        C = [C, sum(chargerUse(b, tDay(d, 1):tDay(d,96)), 'all') <= 96*charging(b,d)];
    end
end

               

%%%%%%%%%%
% Constraints
%%%%%%%%%%

%%% Power Availability 
% Grid Constraints
gridPowTotal = sum(gridPowToB,1) + gridPowToM;
C = [C, 0 <= gridPowTotal <= gridPowAvail]; 

% Solar Power Constraints
solarPowTotal = sum(solarPowToB,1) + solarPowToM;
C = [C, 0 <= solarPowTotal <= solarPowAvail]; 

%%% Main Storage Constraints
C = [C, powerCM == (solarPowToM + gridPowToM)];
C = [C, powerDM ==  sum(mainPowToB,1)];

for t = 1:(T-1)
    C = [C, eM(t+1) == eM(t) + dt*(eff_CM*powerCM(t) - (1/eff_DM)*powerDM(t))]; %#ok<AGROW>
end

C = [C, eM_min <= eM <= eM_max];
C = [C, eM(1) == eM_max*reserveLevel];
C = [C, eM(T) >= eM_max*reserveLevel];
C = [C, 0 <= powerCM <= pCM_max];
C = [C, 0 <= powerDM <= pDM_max]; %#ok<*CHAIN>

%%% Bus Battery Operation

for b = 1:B
    for d = 1:D
        for i = 1:96
            routeDepletion = 0;
            if ~(d == 1 && i == 1)
                t = tDay(d,i);
                for r = 1:R
                    if t == tRet(r,d) % if the route is returning at this time
                        routeDepletion = routeDepletion + eRoute(r)*assignment(b,d,r);
                    end 
                end

                C = [C, eB(b,t) == eB(b,t-1) + dt*powerCB(b,t-1)*eff_CB - routeDepletion];
            end
            
        end
    end
end


for b = 1:B
    for d = 1:D
        for i = 1:96
            t = tDay(d,i);
            routeRequirement = 0;
            for r = 1:R
                if t == tDep(r,d)
                    routeRequirement = eRoute(r)*assignment(b,d,r) + routeRequirement;
                end
            end
            
            C = [C, eB(b,t) >=  eB_min + routeRequirement];
        end
    end
end


C = [C, powerCB == (solarPowToB + gridPowToB + mainPowToB)];

C = [C, eB_min <= eB <= eB_max];

for t = 1:T
    for b = 1:B
            C = [C, 0 <= powerCB(b,t) <= pCB*chargerUse(b,t)]; 
    end
end

C = [C, eB(:,1) == eB_max*busLevel];
C = [C, eB(:,T) == eB_max*busLevel];

%%% Charging Constraints
for t = 1:T
    C = [C, sum(chargerUse(:,t), 1) <= numChargers];
end 

% Route Coverage Constraints
for d = 1:D
    for r = 1:R
        C = [C, sum(assignment(:,d,r), 1) == 1];
    end
end

for b = 1:B
    for d = 1:D
        for r = 1:R
            for t = tDep(r,d):tRet(r,d)
                C = [C, chargerUse(b,t) + assignment(b,d,r) <= 1];
            end
        end
    end
end

for b = 1:B
    for d = 1:D
        C = [C, sum(assignment(b,d,:)) <= 1];
    end
end



% Non Negativity Constraints
C = [C, mainPowToB >= 0];
C = [C, gridPowToM >= 0];
C = [C, gridPowToB >= 0];
C = [C, solarPowToM >= 0];
C = [C, solarPowToB >= 0];
C = [C, eB >= 0];
C = [C, eM >= 0];

% Objective Function to Minimize Operational Costs 
cost = .25 * gridPowTotal * transpose(gridPowPrice);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Solve and Analyze %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Solve the modeled scenario
ops = sdpsettings('verbose',1,'debug',1,'solver','gurobi');
% ops = sdpsettings('verbose',1,'debug',1,'solver','gurobi', 'gurobi.Presolve', 2, 'gurobi.Threads', 10, 'showprogress', 1, 'gurobi.NodefileStart', 8, 'gurobi.MIPGap', 0.005, 'gurobi.MIPFocus', 3);
diagnostics = optimize(C, cost, ops);
isFeasible = ~diagnostics.problem;

% 
% Save Results
% 1-3: 3, 4-8: 5*T, 9:B*T, 10: T, 11:B*D*R
% { 
%     1. paramValue
%     2. isFeasible
%     3. cost
%     4. solarPowAvail(t)
%     5. solarPowTotal(t)
%     6. gridPowTotal(t)
%     7. gridPowAvail(t)
%     8. gridPowToM(t)
%     9. eM(t)
%     10.  eB(b,t)      
%     11. assignment(b,d,r)
% }
cost = value(cost); 
sPA = value(solarPowAvail);
sPT = value(solarPowTotal);
gPT = value(gridPowTotal);
gPA = value(gridPowAvail);
gPM = value(gridPowToM);
eB = reshape(transpose(value(eB)), [B*T, 1]);
eM = value(eM);

sPB = reshape(transpose(value(solarPowToB)), [B*T, 1]);
sPM = value(solarPowToM);
mPB = reshape(transpose(value(mainPowToB)), [B*T, 1]);
gPB = reshape(transpose(value(gridPowToB)), [B*T, 1]);
% assignment is b,d,r
assignments = reshape(value(assignment),[B*D*R,1]);

% c_b,tsu

cU = reshape(value(chargerUse), [B*T, 1]);
% # y1 = mainToB
% # y2 = gridtoB
% # y3 = gridtoM
% # y4 = solartoB
% # y5 = solartomain

results = vertcat(isFeasible,cost,sPA',sPT',gPT', gPA', gPM',eM',eB, assignments, cU);
% results = vertcat(isFeasible,cost,mPB,gPB, gPM', sPB, sPM');

% Save data to proper excel file
writematrix(results, "dynamicBaselineFinal.xlsx");



