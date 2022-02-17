function [eB_final] = showDischarge(eB_init, busAvail, eTransit, nRoutes)

% This function modifies the bus energy data to reflect energy discharge
% during routes.

eB_final = eB_init;

% Initialize a cell array to hold info regarding when routes start and end
B = size(eB_init,1);
T = size(eB_init,2);
routes = cell(B,1);

% Determine when routes start and end
startIndex = 0;
stopIndex = 0;
for b = 1:B
    routeCounter = 1;
    prevAvail = 1;
    for t = 1:T
        currAvail = busAvail(b,t);
        if currAvail == 0 && prevAvail == 1
            startIndex = t;
        elseif currAvail == 1 && prevAvail == 0
            stopIndex = t-1;
            routes{b}(routeCounter, 1) = startIndex;
            routes{b}(routeCounter, 2) = stopIndex;
            routes{b}(routeCounter, 3) = eTransit(b,t-1);
            routeCounter = routeCounter + 1;
        end
        prevAvail = currAvail;
    end
end

% Reflect instant discharge as a linear discharge
for b = 1:B
    R = nRoutes(b);
    for r = 1:R
        startIndex = routes{b}(r, 1);
        stopIndex = routes{b}(r, 2);
        E = routes{b}(r, 3);
        dE = E/(stopIndex - startIndex);
        for t = startIndex:stopIndex
            eB_final(b,t+1) = eB_final(b,t) - dE;
        end
    end
end


    


end

