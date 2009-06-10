% R. McDermott and C. Cruz
% 6-02-2009
% read_dline.m
%
% cfil is the configuration file, for example, '../validation_data_config_matlab.csv'
% vdir is the directory where the experimental data is stored, for example,
%    '../../../Validation/'.
% drange (optional) is a vector for the 'd lines' you want to read from the
%    config file.  For example, [2:5,7:8,10,12].
%
% Dependencies:
%    define_drow_variables.m
%    ../functions/dvcread.m
%    ../functions/parse.m

close all
clear all

cfil = ['../validation_data_config_matlab.csv'];
vdir = ['../../../Validation/'];
drange = 2:2000;

addpath('../functions')
paper_width  = 6.0; % inches
paper_height = 4.5; % inches

A = importdata(cfil);
H = textscan(A{1},'%q','delimiter',',');
headers = H{:}'; clear H

Length_A = length(A);
for i=drange
    if i>Length_A; break; end
    
    P = textscan(A{i},'%q','delimiter',',');
    parameters = P{:}';
    
    if strcmp(parameters(find(strcmp(headers,'switch_id'))),'d')
        
        define_drow_variables
        
        % plot the experimental data or analytical solution
        [H M] = dvcread(d1_Filename,d1_Col_Name_Row);
        d1_Ind_Col = find(strcmp(H,d1_Ind_Col_Name));
        S1 = parse(d1_Dep_Col_Name);
        style = parse(d1_Style);
        for j=1:length(S1)
            d1_Dep_Col = find(strcmp(H,S1(j)));
            if Flip_Axis==0
                X = M(:,d1_Ind_Col)/Scale_Ind;
                Y = M(:,d1_Dep_Col)/Scale_Dep;
            else
                X = M(:,d1_Dep_Col)/Scale_Dep;
                Y = M(:,d1_Ind_Col)/Scale_Ind;
            end
            if Plot_Type=='linear'
                K(j) = plot(X,Y,char(style(j))); hold on
            elseif Plot_Type=='loglog'
                K(j) = loglog(X,Y,char(style(j))); hold on
            end
        end

        % plot the FDS data
        [H M] = dvcread(d2_Filename,d2_Col_Name_Row);
        d2_Ind_Col = find(strcmp(H,d2_Ind_Col_Name));
        S2 = parse(d2_Dep_Col_Name);
        style = parse(d2_Style);
        for j=1:length(S2)
            d2_Dep_Col = find(strcmp(H,S2(j)));
            if Flip_Axis==0
                X = M(:,d2_Ind_Col)/Scale_Ind;
                Y = M(:,d2_Dep_Col)/Scale_Dep;
            else
                X = M(:,d2_Dep_Col)/Scale_Dep;
                Y = M(:,d2_Ind_Col)/Scale_Ind;
            end
            if Plot_Type=='linear'
                K(length(S1)+j) = plot(X,Y,char(style(j)));
            elseif Plot_Type=='loglog'
                K(length(S1)+j) = loglog(X,Y,char(style(j)));
            end
        end
        hold off
        
        % format the legend and axis labels
        set(gca,'FontName','Times')
        set(gca,'FontSize',14)
        if Flip_Axis==0
            xlabel(Ind_Title,'Interpreter','LaTeX','FontSize',16)
            ylabel(Dep_Title,'Interpreter','LaTeX','FontSize',16)
            axis([Min_Ind Max_Ind Min_Dep Max_Dep])
            text(Title_Position(1)*(Max_Ind-Min_Ind)/Scale_Ind,Title_Position(2)*(Max_Dep-Min_Dep)/Scale_Dep,...
                Plot_Title,'FontSize',16,'FontName','Times','Interpreter','LaTeX')
        else
            xlabel(Dep_Title,'Interpreter','LaTeX','FontSize',16)
            ylabel(Ind_Title,'Interpreter','LaTeX','FontSize',16)
            axis([Min_Dep Max_Dep Min_Ind Max_Ind])
            text(Title_Position(1)*(Max_Dep-Min_Dep)/Scale_Dep,Title_Position(2)*(Max_Ind-Min_Ind)/Scale_Ind,...
                Plot_Title,'FontSize',16,'FontName','Times','Interpreter','LaTeX')
        end
        if size(Key_Position)>0
            legend(K,[parse(d1_Key),parse(d2_Key)],'Location',Key_Position,'Interpreter','LaTeX','FontSize',10)
        end
        
        
        % print to pdf
        set(gcf,'Visible','on');
        set(gcf,'PaperUnits','inches');
        set(gcf,'PaperSize',[paper_width paper_height]);
        set(gcf,'PaperPosition',[0 0 paper_width paper_height]); 
        display(['Printing plot ',num2str(i),'...'])
        print(gcf,'-dpdf',['../../../Manuals/',Plot_Filename])
        
    end
    clear S1 S2 K style H M X Y
end
display('Done!')
display('Why?')
why


