clc;
clear;
yalmip('clear');

% Set Size
V = 10;     
D = 7;
T = 4*D; 
R = 5; 
C = [];

% Route Coverage
x = binvar(V, T);
assignment = zeros(V, D, R*4);

% T_V = zeros(V);
T_V = sdpvar(V, 1);

num_pairs = V*(V-1)/2;
M_ij = sdpvar(num_pairs, 1);
M_ija = sdpvar(num_pairs, 1);
M_ijb = sdpvar(num_pairs, 1);

% constraint 1
for t = 1:T-1
    for v = 1:V
        C = [C, x(v, t) + x(v, t+1) <= 1];
    end
end

% constraint 2 
% for every timestep, there is a van assigned to each route
for t = 1:T
    C = [C, sum(x(:, t), 1) == R];
end

% constraint 3
for v = 1:V
    C = [C, T_V(v) == sum(x(v, :), 'all')];
end

% constraint 4 & 6

% 
count = 1;
for i = 1:V
    for j = i:V
        if i ~= j
            C = [C, M_ija(count) - M_ijb(count) == T_V(i) - T_V(j)];
            C = [C, M_ij(count) == M_ija + M_ijb];
            count = count + 1;
        end
    end
end

% nonnegativity 
C = [C, M_ija >= 0];
C = [C, M_ijb >= 0];
C = [C, M_ij >= 0];
C = [C, x >= 0];
C = [C, T_V >= 0];
% C = [C, assignment >= 0];



cost = sum(M_ij, 'all');

% cost=0;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Solve and Analyze %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%s%%%%%%%%%%%%%%
% Solve the modeled scenario
ops = sdpsettings('verbose',1,'debug',1,'solver','gurobi');
% ops = sdpsettings('verbose',1,'debug',1,'solver','gurobi', 'gurobi.Presolve', 2, 'gurobi.Threads', 10, 'showprogress', 1, 'gurobi.NodefileStart', 8, 'gurobi.MIPGap', 0.05, 'gurobi.MIPFocus', 3);
diagnostics = optimize(C, cost, ops);
isFeasible = ~diagnostics.problem;


% % making the assignments

% for t = 1:T
%     day = ceil((t)/4); 
%     r = mod(t-1, 4)+1;
%     idx = find(value(x(:, t)) == 1);
%     for i = idx(1):idx(length(idx))
%         assignment(i, day, r*(i-min(idx)+1)) = 1; 
%     end
% end

for day = 1:D
    for p = 1:4 % parts of the day
        t = (day-1)*4 + p; 
        idx = find(value(x(:, t)) == 1); % the vans which are driving at that time


        routeStart = 1 + (p-1)*5;
        routeEnd = 5 + (p-1)*5;
        
        routes = routeStart:routeEnd;

        for i = 1:5
            van = idx(i);
            route = routes(i);
            assignment(van, day, route) = 1; 
        end
    end
end


save('assignments.mat', "assignment")




