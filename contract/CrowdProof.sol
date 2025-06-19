// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CrowdProof
 * @dev A decentralized crowdfunding platform with proof-of-concept verification
 * @author CrowdProof Team
 */
contract Project {
    
    // State variables
    address public owner;
    uint256 public projectCount;
    
    // Project status enum
    enum ProjectStatus { 
        Active, 
        Funded, 
        Failed, 
        Completed 
    }
    
    // Project structure
    struct CrowdProject {
        uint256 id;
        address creator;
        string title;
        string description;
        uint256 goalAmount;
        uint256 raisedAmount;
        uint256 deadline;
        ProjectStatus status;
        bool proofSubmitted;
        bool proofVerified;
        mapping(address => uint256) contributions;
        address[] contributors;
    }
    
    // Mappings
    mapping(uint256 => CrowdProject) public projects;
    mapping(address => uint256[]) public creatorProjects;
    mapping(address => uint256[]) public contributorProjects;
    
    // Events
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed creator,
        string title,
        uint256 goalAmount,
        uint256 deadline
    );
    
    event ContributionMade(
        uint256 indexed projectId,
        address indexed contributor,
        uint256 amount
    );
    
    event ProofSubmitted(
        uint256 indexed projectId,
        address indexed creator
    );
    
    event ProofVerified(
        uint256 indexed projectId,
        bool verified
    );
    
    event FundsWithdrawn(
        uint256 indexed projectId,
        address indexed creator,
        uint256 amount
    );
    
    event RefundIssued(
        uint256 indexed projectId,
        address indexed contributor,
        uint256 amount
    );
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyProjectCreator(uint256 _projectId) {
        require(
            msg.sender == projects[_projectId].creator,
            "Only project creator can call this function"
        );
        _;
    }
    
    modifier projectExists(uint256 _projectId) {
        require(_projectId > 0 && _projectId <= projectCount, "Project does not exist");
        _;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;
        projectCount = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new crowdfunding project
     * @param _title Project title
     * @param _description Project description
     * @param _goalAmount Funding goal in wei
     * @param _durationDays Project duration in days
     */
    function createProject(
        string memory _title,
        string memory _description,
        uint256 _goalAmount,
        uint256 _durationDays
    ) external {
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(_goalAmount > 0, "Goal amount must be greater than 0");
        require(_durationDays > 0, "Duration must be greater than 0");
        
        projectCount++;
        uint256 deadline = block.timestamp + (_durationDays * 1 days);
        
        CrowdProject storage newProject = projects[projectCount];
        newProject.id = projectCount;
        newProject.creator = msg.sender;
        newProject.title = _title;
        newProject.description = _description;
        newProject.goalAmount = _goalAmount;
        newProject.raisedAmount = 0;
        newProject.deadline = deadline;
        newProject.status = ProjectStatus.Active;
        newProject.proofSubmitted = false;
        newProject.proofVerified = false;
        
        creatorProjects[msg.sender].push(projectCount);
        
        emit ProjectCreated(projectCount, msg.sender, _title, _goalAmount, deadline);
    }
    
    /**
     * @dev Core Function 2: Contribute to a project
     * @param _projectId ID of the project to contribute to
     */
    function contributeToProject(uint256 _projectId) 
        external 
        payable 
        projectExists(_projectId) 
    {
        require(msg.value > 0, "Contribution must be greater than 0");
        
        CrowdProject storage project = projects[_projectId];
        require(project.status == ProjectStatus.Active, "Project is not active");
        require(block.timestamp < project.deadline, "Project deadline has passed");
        require(msg.sender != project.creator, "Creator cannot contribute to own project");
        
        // Add to contributions
        if (project.contributions[msg.sender] == 0) {
            project.contributors.push(msg.sender);
            contributorProjects[msg.sender].push(_projectId);
        }
        
        project.contributions[msg.sender] += msg.value;
        project.raisedAmount += msg.value;
        
        // Check if funding goal is reached
        if (project.raisedAmount >= project.goalAmount) {
            project.status = ProjectStatus.Funded;
        }
        
        emit ContributionMade(_projectId, msg.sender, msg.value);
    }
    
    /**
     * @dev Core Function 3: Submit proof of concept and manage funds
     * @param _projectId ID of the project
     * @param _proofHash IPFS hash or proof identifier
     */
    function submitProofAndManageFunds(uint256 _projectId, string memory _proofHash) 
        external 
        projectExists(_projectId)
        onlyProjectCreator(_projectId)
    {
        CrowdProject storage project = projects[_projectId];
        require(
            project.status == ProjectStatus.Funded || 
            (project.status == ProjectStatus.Active && block.timestamp >= project.deadline),
            "Invalid project status for proof submission"
        );
        require(bytes(_proofHash).length > 0, "Proof hash cannot be empty");
        
        project.proofSubmitted = true;
        
        // Auto-verify if project is funded (simplified verification)
        // In production, this would involve a more complex verification process
        if (project.status == ProjectStatus.Funded) {
            project.proofVerified = true;
            project.status = ProjectStatus.Completed;
            
            // Transfer funds to creator
            uint256 amount = project.raisedAmount;
            project.raisedAmount = 0;
            
            (bool success, ) = payable(project.creator).call{value: amount}("");
            require(success, "Transfer failed");
            
            emit FundsWithdrawn(_projectId, project.creator, amount);
            emit ProofVerified(_projectId, true);
        } else {
            // Project failed to reach goal
            project.status = ProjectStatus.Failed;
            emit ProofVerified(_projectId, false);
        }
        
        emit ProofSubmitted(_projectId, msg.sender);
    }
    
    /**
     * @dev Allow contributors to get refunds for failed projects
     * @param _projectId ID of the project
     */
    function claimRefund(uint256 _projectId) 
        external 
        projectExists(_projectId)
    {
        CrowdProject storage project = projects[_projectId];
        require(
            project.status == ProjectStatus.Failed || 
            (project.status == ProjectStatus.Active && block.timestamp >= project.deadline && project.raisedAmount < project.goalAmount),
            "Refund not available"
        );
        
        uint256 contributionAmount = project.contributions[msg.sender];
        require(contributionAmount > 0, "No contribution found");
        
        project.contributions[msg.sender] = 0;
        project.raisedAmount -= contributionAmount;
        
        (bool success, ) = payable(msg.sender).call{value: contributionAmount}("");
        require(success, "Refund transfer failed");
        
        emit RefundIssued(_projectId, msg.sender, contributionAmount);
    }
    
    // View functions
    function getProject(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId)
        returns (
            uint256 id,
            address creator,
            string memory title,
            string memory description,
            uint256 goalAmount,
            uint256 raisedAmount,
            uint256 deadline,
            ProjectStatus status,
            bool proofSubmitted,
            bool proofVerified
        )
    {
        CrowdProject storage project = projects[_projectId];
        return (
            project.id,
            project.creator,
            project.title,
            project.description,
            project.goalAmount,
            project.raisedAmount,
            project.deadline,
            project.status,
            project.proofSubmitted,
            project.proofVerified
        );
    }
    
    function getProjectContributors(uint256 _projectId) 
        external 
        view 
        projectExists(_projectId)
        returns (address[] memory)
    {
        return projects[_projectId].contributors;
    }
    
    function getContributionAmount(uint256 _projectId, address _contributor) 
        external 
        view 
        projectExists(_projectId)
        returns (uint256)
    {
        return projects[_projectId].contributions[_contributor];
    }
    
    function getCreatorProjects(address _creator) 
        external 
        view 
        returns (uint256[] memory)
    {
        return creatorProjects[_creator];
    }
    
    function getContributorProjects(address _contributor) 
        external 
        view 
        returns (uint256[] memory)
    {
        return contributorProjects[_contributor];
    }
}
