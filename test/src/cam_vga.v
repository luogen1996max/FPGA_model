module cam_vga(    
    input                 sys_clk     ,  //系统时钟
    input                 sys_rst_n   ,  //系统复位，低电平有效
    //摄像头接口
    input                 cam_pclk    ,  //cmos 数据像素时钟
    input                 cam_vsync   ,  //cmos 场同步信号
    input                 cam_href    ,  //cmos 行同步信号
    input        [7:0]    cam_data    ,  //cmos 数据  
	output                cam_rst_n   ,  //cmos 复位信号，低电平有效
    output                cam_pwdn    ,  //cmos 电源休眠模式选择信号
    output                cam_scl     ,  //cmos SCCB_SCL线
    inout                 cam_sda     ,  //cmos SCCB_SDA线
    //SDRAM接口
    output                sdram_clk   ,  //SDRAM 时钟
    output                sdram_cke   ,  //SDRAM 时钟有效
    output                sdram_cs_n  ,  //SDRAM 片选
    output                sdram_ras_n ,  //SDRAM 行有效
    output                sdram_cas_n ,  //SDRAM 列有效
    output                sdram_we_n  ,  //SDRAM 写有效
    output       [1:0]    sdram_ba    ,  //SDRAM Bank地址
    output       [1:0]    sdram_dqm   ,  //SDRAM 数据掩码
    output       [12:0]   sdram_addr  ,  //SDRAM 地址
    inout        [15:0]   sdram_data  ,  //SDRAM 数据    
    //VGA接口                          
    output                vga_hs      ,  //行同步信号
    output                vga_vs      ,  //场同步信号
    output        [15:0]  vga_rgb        //红绿蓝三原色输出 
	);

//parameter define
parameter  SLAVE_ADDR = 7'h3c         ;  //OV5640的器件地址7'h3c
parameter  BIT_CTRL   = 1'b1          ;  //OV5640的字节地址为16位  0:8位 1:16位
parameter  CLK_FREQ   = 26'd65_000_000;  //i2c_dri模块的驱动时钟频率 65MHz
parameter  I2C_FREQ   = 18'd250_000   ;  //I2C的SCL时钟频率,不超过400KHz
parameter  CMOS_H_PIXEL = 24'd1024    ;  //CMOS水平方向像素个数,用于设置SDRAM缓存大小
parameter  CMOS_V_PIXEL = 24'd768     ;  //CMOS垂直方向像素个数,用于设置SDRAM缓存大小
                                      
									  
wire   [15:0]         wr_data         ;  //sdram_ctrl模块写数据
wire   [15:0]         rd_data         ;  //sdram_ctrl模块读数据

//*****************************************************
//**                    main code
//*****************************************************

assign  rst_n = sys_rst_n & locked;
//系统初始化完成：SDRAM和摄像头都初始化完成
//避免了在SDRAM初始化过程中向里面写入数据
//assign  sys_init_done = sdram_init_done & cam_init_done;
//不对摄像头硬件复位,固定高电平
assign  cam_rst_n = 1'b1;
//电源休眠模式选择 0：正常模式 1：电源休眠模式
assign  cam_pwdn = 1'b0;

//锁相环
pll_clk u_pll_clk(
    .areset             (~sys_rst_n),
    .inclk0             (sys_clk),			
    .c0                 (clk_100m),			//100mhz时钟,SDRAM操作时钟
    .c1                 (clk_100m_shift),	//100mhz时钟,SDRAM相位偏移时钟
    .c2                 (clk_65m),			//65mhz时钟,提供给IIC驱动时钟和vga驱动时钟
    .locked             (locked)
    );

//摄像头模块
camera
	#(
	.SLAVE_ADDR			(SLAVE_ADDR),
	.BIT_CTRL  			(BIT_CTRL),
	
	.CLK_FREQ 			(CLK_FREQ) ,
    .I2C_FREQ			(I2C_FREQ),
	
	.CMOS_H_PIXEL      (CMOS_H_PIXEL),
	.CMOS_V_PIXEL      (CMOS_V_PIXEL)
    )
	cam(
	.clk_65m      	  	(clk_65m),
	.rst_n    		  	(rst_n),
		
	.cam_pclk        	(cam_pclk),  //cmos 数据像素时钟
	.cam_vsync       	(cam_vsync),  //cmos 场同步信号
	.cam_href        	(cam_href),  //cmos 行同步信号
	.cam_data        	(cam_data),  //cmos 数据   
	
	//与SDRAM的接口
	.sdram_init_done 	(sdram_init_done),
	.cmos_frame_valid	(wr_en),  //数据有效使能信号
	.cmos_frame_data 	(wr_data),   //有效数据        
	
	.cam_scl        	  	(cam_scl),      // I2C的SCL时钟信号
	.cam_sda              	(cam_sda)// I2C的SDA信号
);



//SDRAM 控制器顶层模块,封装成FIFO接口
//SDRAM 控制器地址组成: {bank_addr[1:0],row_addr[12:0],col_addr[8:0]}
sdram_top u_sdram_top(
    .ref_clk            (clk_100m),                   //sdram 控制器参考时钟
    .out_clk            (clk_100m_shift),             //用于输出的相位偏移时钟
    .rst_n              (rst_n),                      //系统复位
                                                        
    //用户写端口                                        
    .wr_clk             (cam_pclk),                   //写端口FIFO: 写时钟
    .wr_en              (wr_en),                      //写端口FIFO: 写使能
    .wr_data            (wr_data),                    //写端口FIFO: 写数据
    .wr_min_addr        (24'd0),                      //写SDRAM的起始地址
    .wr_max_addr        (CMOS_H_PIXEL*CMOS_V_PIXEL),  //写SDRAM的结束地址
    .wr_len             (10'd512),                    //写SDRAM时的数据突发长度
    .wr_load            (~rst_n),                     //写端口复位: 复位写地址,清空写FIFO
                                                        
    //用户读端口                                        
    .rd_clk             (clk_65m),                    //读端口FIFO: 读时钟
    .rd_en              (rd_en),                      //读端口FIFO: 读使能
    .rd_data            (rd_data),                    //读端口FIFO: 读数据
    .rd_min_addr        (24'd0),                      //读SDRAM的起始地址
    .rd_max_addr        (CMOS_H_PIXEL*CMOS_V_PIXEL),  //读SDRAM的结束地址
    .rd_len             (10'd512),                    //从SDRAM中读数据时的突发长度
    .rd_load            (~rst_n),                     //读端口复位: 复位读地址,清空读FIFO
                                                
    //用户控制端口                                
    .sdram_read_valid   (1'b1),                       //SDRAM 读使能
    .sdram_pingpang_en  (1'b1),                       //SDRAM 乒乓操作使能
    .sdram_init_done    (sdram_init_done),            //SDRAM 初始化完成标志
                                                
    //SDRAM 芯片接口                                
    .sdram_clk          (sdram_clk),                  //SDRAM 芯片时钟
    .sdram_cke          (sdram_cke),                  //SDRAM 时钟有效
    .sdram_cs_n         (sdram_cs_n),                 //SDRAM 片选
    .sdram_ras_n        (sdram_ras_n),                //SDRAM 行有效
    .sdram_cas_n        (sdram_cas_n),                //SDRAM 列有效
    .sdram_we_n         (sdram_we_n),                 //SDRAM 写有效
    .sdram_ba           (sdram_ba),                   //SDRAM Bank地址
    .sdram_addr         (sdram_addr),                 //SDRAM 行/列地址
    .sdram_data         (sdram_data),                 //SDRAM 数据
    .sdram_dqm          (sdram_dqm)                   //SDRAM 数据掩码
    );


//VGA驱动模块
vga_driver u_vga_driver(
    .vga_clk            (clk_65m),    
    .sys_rst_n          (rst_n),    
    
    .vga_hs             (vga_hs),       
    .vga_vs             (vga_vs),       
    .vga_rgb            (vga_rgb),      
        
    .pixel_data         (rd_data), 
    .data_req           (rd_en),                      //请求像素点颜色数据输入
    .pixel_xpos         (), 
    .pixel_ypos         ()
    ); 
   
endmodule
